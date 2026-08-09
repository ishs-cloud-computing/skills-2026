# task-3 — System operation

CloudFront(단일 엔드포인트) → ALB(AWS Load Balancer Controller가 Ingress로 생성) → EKS(t3.medium, Karpenter) 위 user/product/stress + RDS(Proxy) + S3 이미지. **T+60분 트래픽 시작 전 완료가 목표** — 아래를 위에서 아래로 실행한다. 설계 근거·당일 변경 절차·인스턴스 타입별 튜닝은 [ARCHITECTURE.md](ARCHITECTURE.md). Linux/macOS bash 판은 [README.linux.md](README.linux.md).

```
task-3/
├── terraform/   # VPC·ECR·RDS(+Proxy)·S3·CloudFront·WAF   (ALB는 여기 없다)
├── eksctl/      # 클러스터 + Karpenter + MNG 1대 + addon
├── k8s/         # EC2NodeClass/NodePool, 앱별 Deploy+Svc+HPA, Ingress(ALB 전체)
├── db/          # DB 초기화 SQL (STEP 7에서 사용)
└── app/         # Dockerfile (제공 바이너리를 당일 app/ 에 복사)
```

명령은 **두 곳**에서 실행한다. 각 블록 첫 줄 라벨을 보고 해당 위치에 붙여넣는다.
- **Windows PowerShell(본 컴퓨터)**: terraform·eksctl·helm·kubectl·aws 전부. tfstate가 여기 있다. `sed`/`jq` 불필요(값은 `terraform output`으로 읽는다).
- **CloudShell(ap-northeast-2)**: 이미지 빌드/푸시(STEP 3)와 DB 초기화(STEP 7).

> PowerShell에서 `terraform`·`eksctl`·`helm`·`kubectl`·`aws`는 각 `.exe`가 PATH에 있어야 한다(설치 후 새 창). **`helm.exe`가 새로 필요하다** — AWS Load Balancer Controller는 EKS 관리형 addon이 아니라 Helm 차트로만 설치된다.

**ALB는 Terraform이 아니라 Ingress가 만든다.** 그래서 CloudFront(=제출 엔드포인트)는 STEP 6 이후에야 생성 가능하다. 순서를 건너뛰지 말 것.

---

## STEP 0 — 사전 준비 (PowerShell)

당일 과제지와 대조해 먼저 아래 파일을 손본다.

| 파일 | 확인할 값 |
|---|---|
| `terraform/terraform.tfvars` | `bucket_name`(전역 유일), `db_password` |
| `terraform/variables.tf` | `apps`(앱 목록), `image_tag` |
| `terraform/locals.tf` | 리전·CIDR·DB 사양, `cluster_name`, `alb_name` |

`db_password`를 적는 곳은 tfvars 한 곳뿐이다. 앱 매니페스트에 넣을 값은 STEP 6에서 `terraform output`으로 읽으므로 셸 환경변수를 따로 맞출 필요가 없다.
`cluster_name`·`alb_name`·앱 목록을 바꿀 때 함께 고쳐야 하는 짝은 [ARCHITECTURE.md](ARCHITECTURE.md)의 "파일 간 결합" 표에 있다.

```powershell
# ── Windows PowerShell ──
cd task-3
aws configure   # 지급 키 입력, region: ap-northeast-2
```

## STEP 1 — 선행 apply: 네트워크·ECR·S3 → RDS (PowerShell, ~3분 + ~15분)

CloudFront·WAF·S3 정책은 ALB가 생겨야 하므로 STEP 7로 미룬다. 여기서는 나머지를 전부 만든다.
리프 리소스만 지정 — VPC·서브넷·IGW·NAT·라우트는 종속성으로 딸려 온다.
apply를 **1a(짧음) / 1b(RDS, 김)** 로 나눈다. 근거는 [ARCHITECTURE.md](ARCHITECTURE.md)의 "apply를 1a/1b로 나누는 이유".

### 1a — 네트워크·ECR·S3 (~3분)

```powershell
# ── Windows PowerShell ──
terraform -chdir=terraform init
$targets = @(
  "-target=aws_vpc_endpoint.s3"
  "-target=aws_nat_gateway.this"
  "-target=aws_route_table_association.public"
  "-target=aws_route_table_association.private"
  "-target=aws_ecr_repository.app"
  "-target=aws_s3_bucket.this"
)

terraform -chdir=terraform apply -auto-approve @targets
terraform -chdir=terraform output -json private_subnet_ids   # 2개 id가 에러 없이 나와야 한다
```

> **여기서 두 번째 창을 열어 STEP 2(eksctl)를 시작한다.** 위 output이 성공하는 것이 그 신호다.
> 1a가 끝나기 전에 STEP 2를 시작하면 output이 아직 state에 없어 실패한다.

### 1b — RDS + Proxy (~15분, STEP 2와 병렬)

이 창에서 이어서 실행한다. 이 target 하나가 DB 인스턴스·프록시·Secret·SG·IAM 역할을 전부 물고 온다.

```powershell
# ── Windows PowerShell (첫 번째 창) ──
terraform -chdir=terraform apply -auto-approve "-target=aws_db_proxy_target.this"

aws secretsmanager describe-secret --secret-id skills-db-credentials --query VersionIdsToStages
# {"<uuid>": ["AWSCURRENT"]} 이 나와야 한다. {} 또는 null이면 secret이 비어 있어
# 프록시가 DB에 인증하지 못한다 → terraform apply를 target 없이 다시 실행
```

## STEP 2 — eksctl 클러스터 생성 (새 PowerShell 창, ~20분)

STEP 1b와 병렬. 이 창은 생성이 끝날 때까지 점유되므로 STEP 3은 CloudShell에서 병행한다.

```powershell
# ── Windows PowerShell (두 번째 창) ──
cd task-3
$prv = terraform -chdir=terraform output -json private_subnet_ids | ConvertFrom-Json
$pub = terraform -chdir=terraform output -json public_subnet_ids  | ConvertFrom-Json
$prv; $pub   # subnet- id가 총 4개 나와야 한다. 비면 STEP 1a 미완료 — 진행 금지

$yaml = Get-Content eksctl/cluster.yaml -Raw
$yaml = $yaml.Replace('subnet-REPLACE_PRIVATE_A', $prv[0]).Replace('subnet-REPLACE_PRIVATE_B', $prv[1])
$yaml = $yaml.Replace('subnet-REPLACE_PUBLIC_A',  $pub[0]).Replace('subnet-REPLACE_PUBLIC_B',  $pub[1])
$yaml | Set-Content eksctl/cluster.rendered.yaml

Select-String 'REPLACE' eksctl/cluster.rendered.yaml   # 출력이 없어야 한다(치환 누락 검사)

eksctl create cluster -f eksctl/cluster.rendered.yaml   # kubeconfig 자동 병합
```

> **`karpenter.version`이 실패하면**: eksctl은 상한이 아니라 하한(0.28.0)만 검사하므로 거절은 대개 그 버전의 Helm 차트가 없다는 뜻이다. Karpenter 호환성 매트릭스에서 실재하는 stable로 내려 다시 실행한다(k8s 1.36은 Karpenter >= 1.13). 그래도 안 되면 `karpenter:` 블록을 지우고 클러스터만 만든 뒤 [공식 Getting Started](https://karpenter.sh/docs/getting-started/)의 Helm 절차로 직접 설치한다.

## STEP 3 — 이미지 빌드/푸시 (CloudShell, 바이너리 수령 즉시)

ECR 레포는 STEP 1a terraform이 생성했다 — 레포명 = `variables.tf`의 `apps` 항목 = k8s 이미지명.
Dockerfile 수정(베이스 교체 등)이 필요하면 `app/Dockerfile` 주석을 참고해 직접 수정한다.

**전제**: CloudShell에서 `git clone <repo> && cd task-3` 후, 제공 바이너리를 `app/` 아래에 파일명 `user`·`product`·`stress`로 복사해 둔다.

3개를 모두 빌드하되 **여기서 push하지 않는다** — 3a~3c 검증을 통과한 뒤 3d에서 한 번에 올린다.
당일 앱 목록이 다르면 아래 `for` 목록만 바꾼다(`variables.tf`의 `apps`와 동일하게).

```bash
# ── CloudShell(ap-northeast-2) ──
ACCT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCT.dkr.ecr.ap-northeast-2.amazonaws.com
TAG=v1   # terraform의 image_tag 변수와 반드시 일치

aws ecr get-login-password | docker login --username AWS --password-stdin $REG

for a in user product stress; do
  docker build --build-arg BINARY=$a -t $REG/$a:$TAG . || echo "BUILD FAILED: $a"
done
```

### 3a — 링크 방식 확인 (push 전)

```bash
# ── CloudShell ──
file app/user app/product app/stress   # "dynamically linked" / "statically linked"
```

`app/Dockerfile`의 base는 glibc를 포함해 정적·동적 둘 다 돈다. 여기서 볼 것은 **혹시 static 베이스로 되돌렸는지**뿐 — 되돌린 상태에서 동적 링크면 `exec /app/server: no such file or directory`로 즉사한다(바이너리가 아니라 ELF 인터프리터가 없다는 뜻).

### 3b — 스모크: 부팅·포트·healthcheck (push 전)

`stress`는 DB·S3를 안 쓰므로 이걸로 검증이 끝난다.

```bash
# ── CloudShell ──
docker run -d -p 8080:8080 --name test $REG/stress:$TAG

curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/healthcheck   # 200 기대
docker logs test                                                      # 부팅 로그·에러 확인
docker rm -f test
```

### 3c — 계약 테스트: user·product (push 전)

계약 테스트(user·product)는 STEP 1b의 RDS·프록시가 준비된 뒤 **실제 프록시 주소로 개인이 알아서 진행**한다.

### 3d — push

```bash
# ── CloudShell ──
for a in user product stress; do docker push $REG/$a:$TAG; done
aws ecr describe-images --repository-name user --query 'imageDetails[].imageTags' --output text   # TAG 확인
```

## STEP 4 — 컨트롤러 정리 + LBC 설치 (PowerShell)

STEP 2의 `eksctl create`가 끝난 뒤. **Karpenter 축소를 NodePool(STEP 5)보다 먼저** 실행한다 — 순서를 뒤집으면 Karpenter가 자기 자신의 Pending replica를 위해 노드를 1대 더 띄운다. (근거: [ARCHITECTURE.md](ARCHITECTURE.md)의 "유휴 EC2 = 1대")

```powershell
# ── Windows PowerShell ──
kubectl -n karpenter scale deploy/karpenter --replicas=1

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller `
  -n kube-system `
  --set clusterName=skills-eks `
  --set serviceAccount.create=false `
  --set serviceAccount.name=aws-load-balancer-controller `
  --set replicaCount=1

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
kubectl get ingressclass alb   # 차트가 만든다. 없으면 Ingress가 무시된다
```

ServiceAccount와 IAM 역할은 eksctl이 이미 만들었다(`iam.podIdentityAssociations` + `wellKnownPolicies`) — 정책 JSON을 받아 `aws iam create-policy` 할 필요가 없다. Pod Identity라 SA에 `eks.amazonaws.com/role-arn` annotation은 붙지 않는다(정상).

## STEP 5 — 노드풀 적용 (PowerShell)

```powershell
# ── Windows PowerShell ──
kubectl apply -f k8s/00-nodeclass.yaml -f k8s/01-nodepool.yaml
kubectl get ec2nodeclass,nodepool   # Ready 확인
```

## STEP 6 — 앱 + Ingress 배포 (PowerShell)

env는 각 앱 매니페스트에 직접 들어있다. `k8s/rendered/`에 전부 치환해 두고 폴더를 통째로 apply한다 —
알파벳 순 적용이라 Ingress(20)가 마지막이고, 이 Ingress가 LBC에게 ALB를 만들게 하는 방아쇠다.

```powershell
# ── Windows PowerShell ──
$img    = terraform -chdir=terraform output -json ecr_image_uris | ConvertFrom-Json   # 태그 포함 full URI
$proxy  = terraform -chdir=terraform output -raw db_proxy_endpoint
$dbport = terraform -chdir=terraform output -raw db_port
$dbpw   = terraform -chdir=terraform output -raw db_password
$bucket = terraform -chdir=terraform output -raw bucket_name

# 치환 전 검증 — 출력이 없어야 한다. EMPTY가 뜨면 해당 terraform output부터 해결
foreach ($kv in @{IMG_USER=$img.user; IMG_PRODUCT=$img.product; IMG_STRESS=$img.stress;
                  PROXY=$proxy; DBPORT=$dbport; DBPW=$dbpw; BUCKET=$bucket}.GetEnumerator()) {
  if (-not $kv.Value) { Write-Warning "EMPTY: $($kv.Name)" }
}

New-Item -ItemType Directory -Force k8s/rendered | Out-Null

# user (DB만)
$y = Get-Content k8s/10-user.yaml -Raw
$y = $y.Replace('<IMAGE>', $img.user)
$y = $y.Replace('<PROXY_ENDPOINT>', $proxy)
$y = $y.Replace('<DB_PORT>', $dbport)
$y = $y.Replace('<DB_PASSWORD>', $dbpw)
$y | Set-Content k8s/rendered/10-user.yaml

# product (DB + S3)
$y = Get-Content k8s/11-product.yaml -Raw
$y = $y.Replace('<IMAGE>', $img.product)
$y = $y.Replace('<PROXY_ENDPOINT>', $proxy)
$y = $y.Replace('<DB_PORT>', $dbport)
$y = $y.Replace('<DB_PASSWORD>', $dbpw)
$y = $y.Replace('<BUCKET_NAME>', $bucket)
$y | Set-Content k8s/rendered/11-product.yaml

# stress (env 없음 — 이미지만)
$y = Get-Content k8s/12-stress.yaml -Raw
$y = $y.Replace('<IMAGE>', $img.stress)
$y | Set-Content k8s/rendered/12-stress.yaml

# Ingress (치환할 값 없음 — 일괄 apply에 포함)
Copy-Item k8s/20-ingress.yaml k8s/rendered/

# 치환 후 검증 — 출력이 없어야 한다(placeholder 잔존 검사, 주석 속 <...>는 제외)
Select-String '^[^#]*<[A-Z_]+>' k8s/rendered/*.yaml

kubectl apply -f k8s/rendered/

kubectl get pods -w                       # Running 확인
kubectl get ingress skills -w             # ADDRESS에 ALB DNS가 뜰 때까지 (~3분)
```

ADDRESS가 비어 있으면 `kubectl -n kube-system logs deploy/aws-load-balancer-controller`로 원인을 본다. 흔한 원인은 퍼블릭 서브넷의 `kubernetes.io/role/elb` 태그 누락(terraform `vpc.tf`)이다.

## STEP 7 — CloudFront 생성 + 엔드포인트 제출 (PowerShell)

Ingress의 ADDRESS가 뜬 뒤 실행한다. `data "aws_lb"`가 그 ALB를 조회해 origin에 건다.

```powershell
# ── Windows PowerShell ──
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.
CloudFront는 `wait_for_deployment=false`라 도메인이 즉시 나온다(전파는 몇 분 더 걸린다).

## STEP 8 — DB 초기화 (RDS 콘솔 → CloudShell)

STEP 1b의 RDS가 생성됐으면 언제든 실행 가능하며, STEP 5~7과 병행해도 된다.

RDS 콘솔 → DB `apdev-rds-instance` → **Connectivity & security** → **Connect using CloudShell** 클릭.
버튼이 접속 명령(엔드포인트·유저 포함)을 자동 입력한다 → Enter → password 입력. RDS **인스턴스** 콘솔에서 열리므로 자동으로 직결 엔드포인트다(프록시 아님 — 대량 적재가 프록시에 피닝되는 것을 피한다). `:exit`로 나오면 접속 명령이 히스토리(↑)에 남아 재사용할 수 있다.

**먼저 과제지의 스키마와 `db/01-schema.sql`을 대조한다.** 다르면 `db/` 안의 파일을 과제지에 맞게 고치고 진행한다.

1. **스키마** — `vim 01-schema.sql`로 `db/01-schema.sql` 내용을 붙여넣고 저장한 뒤, 히스토리의 접속 명령 뒤에 `< 01-schema.sql`을 붙여 실행.

2. **admin 유저 native 플러그인 전환** — 프록시 클라이언트 인증이 MySQL Native(`terraform/rds-proxy.tf`)라 백엔드 admin도 native여야 한다. `mysql>` 프롬프트에서 직접 입력(비밀번호가 들어가므로 파일로 남기지 않는다):

   ```sql
   ALTER USER 'admin'@'%' IDENTIFIED WITH mysql_native_password BY '<PASSWORD>';
   ```

   `<PASSWORD>`는 `terraform/terraform.tfvars`의 `db_password` 값이다.

   > **여기서 STEP 6(앱 배포)을 시작해도 된다.** 스키마·인증이 끝났으므로 앱은 빈 테이블에 정상 연결되고, 데이터는 T+60 트래픽 전에만 있으면 된다.

3. **제공 dump 적재** (느림) — `vim load_user.dump`로 붙여넣고 저장한 뒤 같은 방식으로 적재. dump가 커서 붙여넣기가 비현실적이면 S3에 올리고 `aws s3 cp s3://<bucket>/load_user.dump .`로 내려받는다.

4. **email 인덱스** (`db/02-index.sql`, dump 적재 **후**) — `GET /v1/user?email=`이 유일한 조회 패턴인데 과제지 스키마에 email 인덱스가 없다(풀스캔 = 0.2s SLO 전멸). dump가 DROP/CREATE TABLE을 포함할 수 있으므로 반드시 dump 뒤에 실행한다.

5. **검증** — `mysql>`에서:

   ```sql
   SELECT COUNT(*) FROM user;
   SHOW INDEX FROM user;
   SELECT user, plugin FROM mysql.user WHERE user='admin';
   ```

   기대값: 행 수 = dump 건수, `idx_email` 존재, plugin = `mysql_native_password`.

## STEP 9 — 검증 (PowerShell)

전제: PS 7.3 이상(`$PSVersionTable.PSVersion`) — 미만이면 `-d`의 JSON 따옴표가 벗겨져 400이 난다.
`curl.exe`로 명시한다(PS7은 무관하지만, 5.1 창에 잘못 붙여넣어도 Invoke-WebRequest로 오작동하지 않게).
`/images/...` 경로의 오브젝트 키는 STEP 3c에서 확인한 실제 키로 바꾼다.

```powershell
# ── Windows PowerShell ──
$CF = "https://$(terraform -chdir=terraform output -raw cloudfront_domain)"
$Q  = "requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
function c($url) { curl.exe -s -o NUL -w "%{http_code} %{time_total}s $url`n" $url }

# user — POST(생성) → GET(조회)
curl.exe -s -o NUL -w "%{http_code} POST user`n" -X POST "$CF/v1/user?$Q" `
  -H 'Content-Type: application/json' `
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","username":"dbdump500001","email":"dbdump500001@example.org"}'  # 201
c "$CF/v1/user?email=dbdump500001@example.org&$Q"                          # 200

# product — POST(생성) → GET(조회)
curl.exe -s -o NUL -w "%{http_code} POST product`n" -X POST "$CF/v1/product?$Q" `
  -H 'Content-Type: application/json' `
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","id":"dbdump500001","name":"dbdump500001","price":1234}'  # 201
c "$CF/v1/product?id=dbdump500001&$Q"                                      # 200

# product 이미지 업로드(PUT) → /images 다운로드
[IO.File]::WriteAllBytes("$env:TEMP\smoke.jpg", [byte[]]::new(1024))
curl.exe -s -o NUL -w "%{http_code} PUT product image`n" -X PUT "$CF/v1/product?$Q" `
  -F "requestid=999999999999" -F "uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729" `
  -F "id=dbdump500001" -F "image=@$env:TEMP\smoke.jpg"                     # 200
c "$CF/images/dbdump500001.jpg"                                           # 200

# stress (DB 미사용)
curl.exe -s -o NUL -w "%{http_code} POST stress`n" -X POST "$CF/v1/stress?$Q" `
  -H 'Content-Type: application/json' `
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'  # 201

# 비정상 요청
c "$CF/v1/none?$Q"                                                         # 404 (Ingress fixed-response)
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                  # 403 (WAF SQLi)
```

## STEP 10 — 유휴 1대 확인 (PowerShell)

**비용 ratio의 전제**다. 트래픽이 없을 때 running EC2가 1대여야 한다.

```powershell
# ── Windows PowerShell ──
kubectl get nodes                                                  # 1개
kubectl -n karpenter get deploy karpenter                          # 1/1
kubectl -n kube-system get deploy aws-load-balancer-controller     # 1/1
kubectl get pods -A --field-selector status.phase=Pending          # 비어 있어야 한다
kubectl get nodeclaims                                             # 유휴 시 0개
aws ec2 describe-instances --filters Name=instance-state-name,Values=running `
  --query 'length(Reservations[].Instances[])'                     # 1
```

Pending 파드가 하나라도 남아 있으면 Karpenter가 노드를 띄워 1대가 깨진다 — 4번째 명령이 핵심이다.
노드 1대에 안 들어가면 조정 순서는 ① `kubectl -n kube-system scale deploy/coredns --replicas=1`
→ ② 앱 requests 200m로 → ③ MNG를 2대로 (`eksctl scale nodegroup`).

## STEP 11 — 운영 (PowerShell)

```powershell
# ── Windows PowerShell ──
kubectl top nodes; kubectl top pods; kubectl get hpa -w   # 스케일 동작 관찰
kubectl get nodeclaims -w                                 # Karpenter 노드 증감
```

콘솔에서 볼 것:
- CloudWatch → Logs Insights: WAF 로그 쿼리 세트는 `queries/` (앱 stdout은 `kubectl logs`)
- WAF 콘솔(us-east-1) → sampled requests: SQLi·KnownBadInputs 룰 매치 확인

당일 변경:
- 특정 공격 패턴 추가 차단: `terraform/waf.tf`에 관리형 룰 블록 추가([ARCHITECTURE.md](ARCHITECTURE.md)의 붙여넣기용 블록)
- DB 엔진·API·인스턴스 타입 변경 절차: [ARCHITECTURE.md](ARCHITECTURE.md)의 "당일 변경 시나리오"
