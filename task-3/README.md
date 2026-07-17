# task-3 — System operation

CloudFront(단일 엔드포인트) → internet-facing ALB(SG=CloudFront prefix list) → EKS Auto Mode(t3.medium) 위 user/product/stress + RDS(Proxy) + S3 이미지. **T+60분 트래픽 시작 전 완료가 목표** — 아래를 위에서 아래로 실행한다. 설계 근거·당일 변경 절차·인스턴스 타입별 튜닝은 [ARCHITECTURE.md](ARCHITECTURE.md). Linux/macOS bash 판은 [README.linux.md](README.linux.md).

```
task-3/
├── terraform/   # VPC·ECR·RDS(+Proxy)·S3·ALB·CloudFront·WAF·노드 IAM
├── eksctl/      # Auto Mode 클러스터 (+ metrics-server, cloudwatch addon)
├── k8s/         # NodeClass/NodePool, 앱별 Deploy+Svc+TGB+HPA+PDB
├── db/          # DB 초기화 SQL + 런북 (STEP 7에서 진입)
└── app/         # Dockerfile (제공 바이너리를 당일 app/ 에 복사)
```

명령은 **두 곳**에서 실행한다. 각 블록 첫 줄 라벨을 보고 해당 위치에 붙여넣는다.
- **Windows PowerShell(본 컴퓨터)**: terraform·eksctl·kubectl·aws 전부. tfstate가 여기 있다. `sed`/`jq` 불필요(값은 `terraform output`으로 읽는다). aws CLI는 kubectl의 EKS 인증(`aws eks get-token`)에도 쓰인다.
- **CloudShell(ap-northeast-2)**: 이미지 빌드/푸시만(STEP 4). 로컬에 Docker가 없어도 되는 유일한 이유.

> PowerShell에서 `terraform`·`eksctl`·`kubectl`·`aws`는 각 `.exe`가 PATH에 있어야 한다(설치 후 새 창).

---

## STEP 0 — 사전 준비 (PowerShell)

```powershell
# ── Windows PowerShell ──
cd task-3
# terraform/terraform.tfvars 수정: player_number, db_password(default: password)
# 앱 목록·이미지 태그가 당일 과제와 다르면 terraform/variables.tf의 apps·image_tag,
# 리전·CIDR·DB 사양이 다르면 terraform/locals.tf 수정

# AWSCLI 로그인
aws configure   # region: ap-northeast-2

$env:DB_PASSWORD = 'password'   # tfvars의 db_password와 동일하게 (STEP 8 치환용)
```

## STEP 1 — 선행 apply: 네트워크·노드롤 (PowerShell, ~3분)

리프 리소스만 지정 — VPC·서브넷·IGW·NAT·라우트·노드롤은 종속성으로 딸려 온다.

```powershell
# ── Windows PowerShell ──
terraform -chdir=terraform init
$targets = @(
  "-target=aws_vpc_endpoint.s3"
  "-target=aws_nat_gateway.this"
  "-target=aws_route_table_association.public"
  "-target=aws_route_table_association.private"
  "-target=aws_iam_role_policy_attachment.node_minimal"
  "-target=aws_iam_role_policy_attachment.node_ecr_pull"
  "-target=aws_ecr_repository.app"
)

terraform -chdir=terraform apply -auto-approve @targets
```

## STEP 2 — eksctl 클러스터 생성 (PowerShell, ~15분)

이 창은 생성이 끝날 때까지 점유되므로, **바로 STEP 3을 새 PowerShell 창에서 병렬로** 돌린다.

```powershell
# ── Windows PowerShell ──
$sn   = terraform -chdir=terraform output -json private_subnet_ids | ConvertFrom-Json
$acct = aws sts get-caller-identity --query Account --output text

$yaml = Get-Content eksctl/cluster.yaml -Raw
$yaml = $yaml.Replace('subnet-REPLACE_A', $sn[0])
$yaml = $yaml.Replace('subnet-REPLACE_B', $sn[1])
$yaml = $yaml.Replace('ACCOUNT_ID', $acct)
$yaml | Set-Content -Encoding ascii eksctl/cluster.rendered.yaml

eksctl create cluster -f eksctl/cluster.rendered.yaml   # kubeconfig 자동 병합
```

## STEP 3 — 전체 terraform apply (새 PowerShell 창, ~20분)

STEP 2와 병렬. 자격증명은 aws configure로 저장돼 전 창 공유 — **새 창에서는 `$env:DB_PASSWORD`만 다시 설정**한 뒤:

```powershell
# ── Windows PowerShell (두 번째 창) ──
cd task-3
terraform -chdir=terraform apply -auto-approve
```

RDS Multi-AZ·CloudFront 배포가 오래 걸린다. CloudFront 도메인은 배포 완료 전 확정되므로 STEP 6에서 미리 제출한다.

## STEP 4 — 이미지 빌드/푸시 (CloudShell, 바이너리 수령 즉시)

ECR 레포는 STEP 1 terraform이 생성했다 — 레포명 = `variables.tf`의 `apps` 맵 키 = k8s 이미지명.
Dockerfile 수정(베이스 교체 등)이 필요하면 `app/Dockerfile` 주석을 참고해 직접 수정한다.

```bash
# ── CloudShell(ap-northeast-2) ──
# 준비: git clone <repo> && cd task-3
#       제공 바이너리를 app/ 아래에 파일명 user·product·stress 로 복사.
ACCT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCT.dkr.ecr.ap-northeast-2.amazonaws.com
TAG=v1   # terraform의 image_tag 변수와 반드시 일치

aws ecr get-login-password | docker login --username AWS --password-stdin $REG

# 3개 모두 빌드 — 아래 4a~4c 검증이 끝난 뒤 4d에서 push한다.
# 당일 앱 목록이 다르면 이 목록만 바꾼다(terraform variables.tf의 apps 맵 키와 동일).
for a in user product stress; do
  docker build --build-arg BINARY=$a -t $REG/$a:$TAG . || echo "BUILD FAILED: $a"
done
```

### 4a — 링크 방식 확인 (push 전)

```bash
# ── CloudShell ──
file app/user app/product app/stress   # "dynamically linked" / "statically linked"
```

`app/Dockerfile`의 base는 glibc를 포함해 정적·동적 둘 다 돈다. 여기서 볼 것은 **혹시 static 베이스로 되돌렸는지**뿐 — 되돌린 상태에서 동적 링크면 `exec /app/server: no such file or directory`로 즉사한다(바이너리가 아니라 ELF 인터프리터가 없다는 뜻).

### 4b — 스모크: 부팅·포트·healthcheck (push 전)

`stress`는 DB·S3를 안 쓰므로 이걸로 검증이 끝난다.

```bash
# ── CloudShell ──
docker run -d -p 8080:8080 --name test $REG/stress:$TAG

curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/healthcheck   # 200 기대
docker logs test                                                      # 부팅 로그·에러 확인
docker rm -f test
```

### 4c — 계약 테스트: user·product (push 전, ~3분)

STEP 3 terraform이 도는 동안 진행 — 임계경로 밖이다. 로컬 mysql에 `db/01-schema.sql`을 그대로 먹여 앱을 붙인다.

```bash
# ── CloudShell ──
docker run -d --name db -e MYSQL_ROOT_PASSWORD=pw -e MYSQL_DATABASE=dev \
  public.ecr.aws/docker/library/mysql:8.0
sleep 20   # mysqld 기동 대기
docker exec -i db mysql -uroot -ppw dev < db/01-schema.sql

docker run -d --link db --name test -p 8080:8080 \
  -e MYSQL_HOST=db -e MYSQL_PORT=3306 -e MYSQL_DBNAME=dev \
  -e MYSQL_USER=root -e MYSQL_PASSWORD=pw $REG/user:$TAG

Q="requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
curl -s -o /dev/null -w '%{http_code} POST user\n' -X POST "localhost:8080/v1/user?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","username":"t1","email":"t1@example.org"}'   # 201
curl -s -o /dev/null -w '%{http_code} GET user\n' "localhost:8080/v1/user?email=t1@example.org&$Q"   # 200
docker rm -f test
```

product는 S3까지 태워 **버킷 env 키·멀티파트 필드명·오브젝트 키**를 한 번에 확정한다 (STEP 3에서 버킷이 생긴 뒤. CloudShell에는 자격증명이 있다).

```bash
# ── CloudShell ── (STEP 3 완료 후)
BUCKET=<STEP 3의 bucket_name>
docker run -d --link db --name test -p 8080:8080 \
  -e MYSQL_HOST=db -e MYSQL_PORT=3306 -e MYSQL_DBNAME=dev \
  -e MYSQL_USER=root -e MYSQL_PASSWORD=pw \
  -e S3_BUCKET=$BUCKET -e AWS_REGION=ap-northeast-2 $REG/product:$TAG

curl -s -o /dev/null -w '%{http_code} POST product\n' -X POST "localhost:8080/v1/product?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","id":"t1","name":"t1","price":1234}'   # 201
head -c 1024 /dev/urandom > /tmp/t.jpg
curl -s -o /dev/null -w '%{http_code} PUT product\n' -X PUT "localhost:8080/v1/product?$Q" \
  -F "requestid=999999999999" -F "uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729" \
  -F "id=t1" -F "image=@/tmp/t.jpg"      # 200. 400/415면 필드명이 틀린 것 → docker logs t 로 확인
aws s3 ls s3://$BUCKET --recursive       # 실제 오브젝트 키 포맷 확인 → STEP 9의 /images/<key> 검증에 사용
docker logs test                         # 버킷 env 키가 틀리면 여기서 S3 에러가 보인다
docker rm -f test db
```

여기서 확정되는 것 — 안 하면 전부 STEP 9(≈T+45)에서 CloudFront·WAF·ALB·TGB·파드 5개 레이어 너머로 발견된다:
- 앱이 `MYSQL_*` env를 실제로 읽는지 (과제지 표와 일치하나 미검증)
- `/healthcheck`가 DB를 건드리는지 → **STEP 7↔8 병행 가능 여부를 결정한다**
- product 버킷 env 키 (`ARCHITECTURE.md`가 "당일 확인 필수"로 남긴 미지수). 틀리면 `k8s/11-product.yaml`의 그 2줄만 고친다
- PUT 멀티파트 필드명과 업로드 오브젝트 키 (STEP 9가 "바이너리로 확인 필수"로 남긴 미지수)

### 4d — push

```bash
# ── CloudShell ──
for a in user product stress; do docker push $REG/$a:$TAG; done
aws ecr describe-images --repository-name user --query 'imageDetails[].imageTags' --output text   # TAG 확인
```

## STEP 5 — 클러스터 완료 후 노드풀 적용 (PowerShell)

STEP 2 창에서 `eksctl create`가 끝난 것을 확인한 뒤:

```powershell
# ── Windows PowerShell ──
kubectl apply -f k8s/00-nodeclass.yaml -f k8s/01-nodepool.yaml
kubectl get nodeclass,nodepool   # Ready 확인
```

## STEP 6 — 엔드포인트 제출 (PowerShell)

앱 배포 전에 미리 제출한다. STEP 3 apply가 CloudFront까지 끝났으면 값이 나온다.

```powershell
# ── Windows PowerShell ──
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.

## STEP 7 — DB 초기화 (PowerShell)

[db/README.md](db/README.md) 런북을 실행한다. 직결 엔드포인트 사용(프록시 X). **STEP 5 노드풀 Ready 필요** (mysql 클라이언트를 `kubectl run`으로 띄운다).
스키마 → admin native 전환 → **여기서 STEP 8을 새 창에서 시작** → dump 적재 → email 인덱스 → 검증 순.

## STEP 8 — 앱 배포: placeholder 치환 후 apply (PowerShell)

**STEP 7의 2번(admin native 전환)이 끝났으면 dump 적재와 병행한다** — 앱은 빈 테이블에도 정상 연결되고(스키마 존재·인증 완료) 데이터는 T+60 트래픽 전에만 있으면 된다. 병행하면 노드 생성·이미지 pull·파드 기동·TG 등록·ALB 헬스체크가 dump 적재 뒤에 쌓이지 않는다.

env는 각 앱 매니페스트에 직접 들어있다. 한 파일씩 치환 후 apply.

```powershell
# ── Windows PowerShell ──
$img    = terraform -chdir=terraform output -json ecr_image_uris | ConvertFrom-Json   # 태그 포함 full URI
$tg     = terraform -chdir=terraform output -json tg_arns | ConvertFrom-Json
$proxy  = terraform -chdir=terraform output -raw db_proxy_endpoint
$dbport = terraform -chdir=terraform output -raw db_port
$bucket = terraform -chdir=terraform output -raw bucket_name

# user (DB만)
$y = Get-Content k8s/10-user.yaml -Raw
$y = $y.Replace('<IMAGE>', $img.user)
$y = $y.Replace('<TG_ARN>', $tg.user)
$y = $y.Replace('<PROXY_ENDPOINT>', $proxy)
$y = $y.Replace('<DB_PORT>', $dbport)
$y = $y.Replace('<DB_PASSWORD>', $env:DB_PASSWORD)
$y | kubectl apply -f -

# product (DB + S3)
$y = Get-Content k8s/11-product.yaml -Raw
$y = $y.Replace('<IMAGE>', $img.product)
$y = $y.Replace('<TG_ARN>', $tg.product)
$y = $y.Replace('<PROXY_ENDPOINT>', $proxy)
$y = $y.Replace('<DB_PORT>', $dbport)
$y = $y.Replace('<DB_PASSWORD>', $env:DB_PASSWORD)
$y = $y.Replace('<BUCKET_NAME>', $bucket)
$y | kubectl apply -f -

# stress (env 없음 — 이미지·TG만)
$y = Get-Content k8s/12-stress.yaml -Raw
$y = $y.Replace('<IMAGE>', $img.stress)
$y = $y.Replace('<TG_ARN>', $tg.stress)
$y | kubectl apply -f -

kubectl get pods -w   # Running 확인 (첫 파드가 노드 생성을 트리거, ~2분)
```

## STEP 9 — 검증 (PowerShell)

PowerShell의 `curl`은 Invoke-WebRequest 별칭이므로 반드시 **`curl.exe`**를 쓴다.

```powershell
# ── Windows PowerShell ──
$CF = "https://$(terraform -chdir=terraform output -raw cloudfront_domain)"
$Q  = "requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
function c($url) { curl.exe -s -o NUL -w "%{http_code} %{time_total}s $url`n" $url }

# user — POST(생성) → GET(조회). dbdump500001은 dump에 없어 신규 생성됨.
curl.exe -s -o NUL -w "%{http_code} POST user`n" -X POST "$CF/v1/user?$Q" `
  -H 'Content-Type: application/json' `
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","username":"dbdump500001","email":"dbdump500001@example.org"}'  # 201
c "$CF/v1/user?email=dbdump500001@example.org&$Q"                          # 200

# product — POST(생성) → GET(조회). 테이블은 비어 있음(dump는 user만).
curl.exe -s -o NUL -w "%{http_code} POST product`n" -X POST "$CF/v1/product?$Q" `
  -H 'Content-Type: application/json' `
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","id":"dbdump500001","name":"dbdump500001","price":1234}'  # 201
c "$CF/v1/product?id=dbdump500001&$Q"                                      # 200

# product 이미지 업로드(PUT) → /images 다운로드. 멀티파트 필드명·오브젝트 키는 제공 바이너리로 확인 필수.
[IO.File]::WriteAllBytes("$env:TEMP\smoke.jpg", (New-Object byte[] 1024))
curl.exe -s -o NUL -w "%{http_code} PUT product image`n" -X PUT "$CF/v1/product?$Q" `
  -F "requestid=999999999999" -F "uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729" `
  -F "id=dbdump500001" -F "image=@$env:TEMP\smoke.jpg"                     # 200
c "$CF/images/dbdump500001.jpg"                                           # 200 (PUT 업로드 후, 키는 바이너리 확인)

# stress (DB 미사용)
curl.exe -s -o NUL -w "%{http_code} POST stress`n" -X POST "$CF/v1/stress?$Q" `
  -H 'Content-Type: application/json' `
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'  # 201

# 비정상 요청
c "$CF/v1/none?$Q"                                                         # 404
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                  # 403 (WAF SQLi)

# 타깃 등록 상태
kubectl get targetgroupbindings
$tg = terraform -chdir=terraform output -json tg_arns | ConvertFrom-Json
aws elbv2 describe-target-health --target-group-arn $tg.user
```

## STEP 10 — 운영 (PowerShell)

```powershell
# ── Windows PowerShell ──
kubectl top nodes; kubectl top pods; kubectl get hpa -w   # 스케일 동작 관찰
# CloudWatch → Container Insights / Logs Insights (앱 stdout 액세스 로그)
# WAF 콘솔(us-east-1) → sampled requests: SQLi·KnownBadInputs 룰 매치 확인
```

- 당일 특정 공격 패턴 추가 차단: `terraform/waf.tf`에 관리형 룰 블록을 하나 더 추가(ARCHITECTURE.md 참고)
- 당일 DB 엔진·API·인스턴스 타입 변경 절차: [ARCHITECTURE.md](ARCHITECTURE.md)의 "당일 변경 시나리오"
