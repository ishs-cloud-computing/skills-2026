# task-3 — System operation

CloudFront(단일 엔드포인트) → internet-facing ALB(SG=CloudFront prefix list) → EKS Auto Mode(t3.medium) 위 user/product/stress + RDS(Proxy) + S3 이미지. **T+60분 트래픽 시작 전 완료가 목표** — 아래를 위에서 아래로 실행한다. 설계 근거·당일 변경 절차·인스턴스 타입별 튜닝은 [ARCHITECTURE.md](ARCHITECTURE.md). Linux/macOS bash 판은 [README.linux.md](README.linux.md).

```
task-3/
├── terraform/   # VPC·RDS(+Proxy)·S3·ECR·ALB·CloudFront·WAF·노드 IAM
├── eksctl/      # Auto Mode 클러스터 (+ metrics-server, cloudwatch addon)
├── k8s/         # NodeClass/NodePool, 앱별 Deploy+Svc+TGB+HPA+PDB
├── db/          # DB 초기화 SQL + 런북 (STEP 7에서 진입)
└── app/         # Dockerfile (제공 바이너리를 당일 app/ 에 복사)
```

명령은 **두 곳**에서 실행한다. 각 블록 첫 줄 라벨을 보고 해당 위치에 붙여넣는다.
- **Windows PowerShell(본 컴퓨터)**: terraform·eksctl·kubectl 전부. tfstate가 여기 있다. `aws`/`sed`/`jq` 불필요(값은 `terraform output`으로 읽는다).
- **CloudShell(ap-northeast-2)**: 이미지 빌드/푸시만(STEP 4). 로컬에 Docker가 없어도 되는 유일한 이유.

> PowerShell에서 `terraform`·`eksctl`·`kubectl`는 각 `.exe`가 PATH에 있어야 한다(설치 후 새 창).

---

## STEP 0 — 사전 준비 (PowerShell)

```powershell
# ── Windows PowerShell ──
cd task-3
# terraform/terraform.tfvars 수정: player_number, (필요시) db_password
# 리전·CIDR·앱 목록·DB 사양이 당일 과제와 다르면 terraform/locals.tf 한 파일만 수정

# 지급된 자격증명(aws CLI 미설치 → 환경변수로 주입). eksctl/kubectl도 이 값을 쓴다.
$env:AWS_ACCESS_KEY_ID     = '<ACCESS_KEY>'
$env:AWS_SECRET_ACCESS_KEY = '<SECRET_KEY>'
$env:AWS_DEFAULT_REGION    = 'ap-northeast-2'
$env:DB_PASSWORD           = 'password'   # tfvars의 db_password와 동일하게
```

## STEP 1 — 선행 apply: 네트워크·노드롤·ECR (PowerShell, ~3분)

eksctl가 참조할 VPC/서브넷과 이미지 push 대상 ECR을 먼저 만든다. 리프 리소스만 지정하면
VPC·서브넷·IGW·NAT·라우트·노드롤은 종속성으로 딸려 온다.

```powershell
# ── Windows PowerShell ──
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve `
  -target=data.aws_caller_identity.current `
  -target=aws_ecr_repository.app `
  -target=aws_vpc_endpoint.s3 `
  -target=aws_nat_gateway.this `
  -target=aws_route_table_association.public `
  -target=aws_route_table_association.private `
  -target=aws_iam_role_policy_attachment.node_minimal `
  -target=aws_iam_role_policy_attachment.node_ecr_pull
```

## STEP 2 — eksctl 클러스터 생성 (PowerShell, ~15분)

서브넷·계정ID를 `terraform output`에서 읽어 `cluster.yaml`을 렌더한 뒤 생성한다.
이 창은 생성이 끝날 때까지 점유되므로, **바로 STEP 3을 새 PowerShell 창에서 병렬로** 돌린다.

```powershell
# ── Windows PowerShell ──
$sn   = terraform -chdir=terraform output -json private_subnet_ids | ConvertFrom-Json
$acct = terraform -chdir=terraform output -raw account_id

$yaml = Get-Content eksctl/cluster.yaml -Raw
$yaml = $yaml.Replace('subnet-REPLACE_A', $sn[0])
$yaml = $yaml.Replace('subnet-REPLACE_B', $sn[1])
$yaml = $yaml.Replace('ACCOUNT_ID', $acct)
$yaml | Set-Content -Encoding ascii eksctl/cluster.rendered.yaml

eksctl create cluster -f eksctl/cluster.rendered.yaml   # kubeconfig 자동 병합
```

## STEP 3 — 전체 terraform apply (새 PowerShell 창, ~20분)

STEP 2와 병렬. **새 창이므로 STEP 0의 자격증명 4줄을 먼저 다시 실행**한 뒤:

```powershell
# ── Windows PowerShell (두 번째 창) ──
cd task-3
terraform -chdir=terraform apply -auto-approve
```

RDS Multi-AZ와 CloudFront 배포가 오래 걸린다. CloudFront 도메인은 배포 완료 전에 확정되므로
STEP 6에서 미리 제출할 수 있다.

## STEP 4 — 이미지 빌드/푸시 (CloudShell, 바이너리 수령 즉시)

CloudShell은 Docker 내장(2024-09부터 전 리전) + x86_64라 제공 바이너리(x86 AL2023 빌드)와
아키텍처가 일치한다. **콘솔 우상단 리전이 ap-northeast-2인지 확인**하고 CloudShell을 연다.

```bash
# ── CloudShell(ap-northeast-2) ──
# 준비: app/(Dockerfile)와 제공 바이너리를 CloudShell에 올린다.
#   git clone <repo> && cd task-3
#   제공 바이너리를 app/ 아래에 파일명 user·product·stress 로 복사.

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $REG

# 앱별로 한 줄씩. 레포 이름은 terraform이 만든 이름(user/product/stress)과 정확히 일치.
# buildkit provenance 매니페스트를 피하려 buildx 대신 classic build+push 사용.
docker build --build-arg BINARY=user    -t $REG/user:v1    app/ && docker push $REG/user:v1
docker build --build-arg BINARY=product -t $REG/product:v1 app/ && docker push $REG/product:v1
docker build --build-arg BINARY=stress  -t $REG/stress:v1  app/ && docker push $REG/stress:v1
```

## STEP 5 — 클러스터 완료 후 노드풀 적용 (PowerShell)

STEP 2 창에서 `eksctl create`가 끝난 것을 확인한 뒤:

```powershell
# ── Windows PowerShell ──
kubectl apply -f k8s/00-nodeclass.yaml -f k8s/01-nodepool.yaml
kubectl get nodeclass,nodepool   # Ready 확인
```

## STEP 6 — 엔드포인트 제출 (PowerShell)

CloudFront 도메인은 EKS 준비와 무관하게 확정되므로 앱 배포 전에 미리 제출한다(조기 제출 = 채점 이득).
STEP 3 apply가 CloudFront까지 끝났으면 값이 나온다.

```powershell
# ── Windows PowerShell ──
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.

## STEP 7 — DB 초기화 (PowerShell)

[db/README.md](db/README.md) 런북을 실행한다. 직결 엔드포인트 사용(프록시 X).
스키마 → dump 적재 → email 인덱스 → admin native 전환 → 검증 순.

## STEP 8 — 앱 배포: placeholder 치환 후 apply (PowerShell)

env는 각 앱 매니페스트에 직접 들어있다(공용 ConfigMap/Secret 없음). 앱마다 필요한 값이 달라
한 파일씩 명시적으로 치환+apply — 당일 한 앱만 바뀌어도 다른 앱에 번지지 않는다.

```powershell
# ── Windows PowerShell ──
$acct   = terraform -chdir=terraform output -raw account_id
$REG    = "$acct.dkr.ecr.ap-northeast-2.amazonaws.com"   # 이미지는 STEP 4(CloudShell)에서 push됨
$tg     = terraform -chdir=terraform output -json tg_arns | ConvertFrom-Json
$proxy  = terraform -chdir=terraform output -raw db_proxy_endpoint
$dbport = terraform -chdir=terraform output -raw db_port
$bucket = terraform -chdir=terraform output -raw bucket_name

# user (DB만)
$y = Get-Content k8s/10-user.yaml -Raw
$y = $y.Replace('<ECR_URL>', "$REG/user")
$y = $y.Replace('<TG_ARN>', $tg.user)
$y = $y.Replace('<PROXY_ENDPOINT>', $proxy)
$y = $y.Replace('<DB_PORT>', $dbport)
$y = $y.Replace('<DB_PASSWORD>', $env:DB_PASSWORD)
$y | kubectl apply -f -

# product (DB + S3)
$y = Get-Content k8s/11-product.yaml -Raw
$y = $y.Replace('<ECR_URL>', "$REG/product")
$y = $y.Replace('<TG_ARN>', $tg.product)
$y = $y.Replace('<PROXY_ENDPOINT>', $proxy)
$y = $y.Replace('<DB_PORT>', $dbport)
$y = $y.Replace('<DB_PASSWORD>', $env:DB_PASSWORD)
$y = $y.Replace('<BUCKET_NAME>', $bucket)
$y | kubectl apply -f -

# stress (env 없음 — 이미지·TG만)
$y = Get-Content k8s/12-stress.yaml -Raw
$y = $y.Replace('<ECR_URL>', "$REG/stress")
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

c "$CF/v1/user?email=dbdump500001@example.org&$Q"                          # 200
c "$CF/v1/product?id=dbdump500001&$Q"                                      # 200
curl.exe -s -o NUL -w "%{http_code}`n" -X POST "$CF/v1/stress?$Q" `
  -H 'Content-Type: application/json' `
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'  # 201
c "$CF/v1/none?$Q"                                                         # 404
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                  # 403 (WAF SQLi)
c "$CF/images/product50001.jpg"                                            # 200 (이미지 업로드 후)

# 타깃 등록 상태
kubectl get targetgroupbindings
$tg = terraform -chdir=terraform output -json tg_arns | ConvertFrom-Json
aws elbv2 describe-target-health --target-group-arn $tg.user   # aws는 CloudShell에서 확인해도 됨
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
