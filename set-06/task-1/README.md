# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 — GJ2026 Book Service Architecture

EKS(Bottlerocket) 위의 Book API 를 CloudFront 단일 엔드포인트(S3 정적 · ALB API · Lambda 조회 · Grafana)로
묶은 결과물을 **Terraform / eksctl / Kubernetes manifest** 로 구성한다.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준(단, CLOUDFRONT scope WAF 는 `us-east-1`).
**NAT 없음 · Private Subnet 2개** — 인터넷 경유가 필요한 이미지는 전부 ECR PTC/미러로 우회한다.
본 PC 단계는 **PowerShell 7** 기준이다 — 본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 쓴다
(CloudShell 단계는 공통).

> **대회 당일에는 [DAY-OF.md](../../DAY-OF.md) 를 먼저 연다.** 과제지는 종이로 배부되어 파일 대조가 안 되므로
> 종이 과제지를 값 대조표로 훑고 다른 값에 형광펜을 친 뒤 이 런북으로 들어온다.
> **set-06 은 아직 DAY-OF 값 대조표·세트 식별표에 없다** — 그래서 아래 값 대조표를 이 문서가 직접 들고 있다.

## 값 대조표

과제지에서 다른 값을 만나면 여기부터 고친다. 전부 `terraform/variables.tf` 기본값이며
`terraform.tfvars` 나 `-var` 로 덮는다. **이름 정확 일치 채점 항목이 많다.**

| 축 | 값 | 어디에 박혀 있나 |
|---|---|---|
| 접두어 | `gj2026` | `var.name_prefix` — 거의 모든 리소스 이름의 앞자리 |
| 비번호 | `-var "bibunho=<선수등번호>"` | S3 버킷 이름 `gj2026-static-<비번호>` |
| 리전 | `ap-northeast-2` (WAF 만 `us-east-1`) | `var.region`, `versions.tf` `aws.use1` |
| VPC / 서브넷 | `10.0.0.0/16`, priv `10.0.10.0/24`·`10.0.11.0/24`, AZ **a/b** | `var.vpc_cidr`, `var.private_subnet_cidrs`, `var.azs` |
| 클러스터 | `gj2026-eks-cluster` 1.35, service CIDR `172.20.0.0/16` | `eksctl/cluster.yaml`, `var.cluster_version` |
| 노드그룹 | `gj2026-eks-addon-nodegroup`(t3.medium) · `gj2026-eks-app-nodegroup`(m5.large), 각 desired 2 | `eksctl/cluster.yaml` |
| 노드명 (채점 4-3) | `gj2026.<instance-id>.(addon\|app).node` | `eksctl/bootstrap/set-hostname-*.sh` |
| DynamoDB | 테이블 `books`, GSI `client_id-index`, PK `booking_id` | `var.table_name`, `var.gsi_name` |
| S3 | `gj2026-static-<비번호>` | `s3.tf` |
| ALB / TG | `gj2026-alb`, `gj2026-book-tg`, `gj2026-grafana-tg` | `alb.tf` |
| WAF | `gj2026-waf-acl` + 룰 `deny-invalid-client-id`·`deny-non-post-on-api` | `waf.tf` |
| KMS alias | `alias/gj2026-{s3,db,eks}-key` | `kms.tf` |
| Lambda | `gj2026-book-reservation`, 런타임 `python3.14` | `var.lambda_runtime` |
| 로그 / 메트릭 | 로그그룹 `/eks/book-svc/access`, 네임스페이스 `gj2026/reservation` | `var.log_group_name`, `var.metric_namespace` |
| 포트 | 앱 `8080`, Grafana `3000` | `var.container_port`, `var.grafana_port` |
| Grafana 계정 | `admin` / `Skills53#` | `k8s/monitoring/grafana-values.yaml` |
| client_id 정규식 | `^[A-Za-z][A-Za-z0-9]*[0-9][A-Za-z0-9]*$` | `var.client_id_regex` (앵커 필수) |

## 디렉토리 구조

```
terraform/   # AWS 인프라 (VPC/Endpoint, KMS, S3, ECR+PTC, DynamoDB, Lambda, ALB, CloudFront, WAF, IAM)
  ├─ versions.tf variables.tf terraform.tfvars
  ├─ vpc.tf kms.tf s3.tf ecr.tf dynamodb.tf
  ├─ lambda.tf lambda/index.py
  ├─ alb.tf cloudfront.tf waf.tf iam.tf outputs.tf
eksctl/
  ├─ cluster.yaml             # EKS 1.35, Bottlerocket, 2 NodeGroup(addon/app), desired 0 으로 생성
  ├─ canary-nodegroup.yaml    # 장애 분리용 최소 노드그룹 (bootstrap 블록 없음)
  └─ bootstrap/               # 노드명 변경 스크립트 (bootstrap container user-data, base64 주입)
k8s/
  ├─ 00-namespace.yaml
  ├─ lbc-values.yaml          # AWS Load Balancer Controller helm values
  ├─ app/                     # ConfigMap, Deployment(book), Service, SecurityGroupPolicy, TargetGroupBinding
  ├─ logging/                 # aws-for-fluent-bit helm values
  └─ monitoring/              # grafana helm values, 대시보드 ConfigMap, grafana TGB
app/Dockerfile                # scratch + 제공 바이너리 (UPX 선압축 + zstd push, 채점 2-2 의 3MB 제한)
README.linux.md               # 본 PC 가 Linux 일 때의 명령 (CloudShell 단계는 공통)
NOTES.md                      # 설계 근거·결정 로그·함정·채점 커버리지
```

> 제공된 배포파일(`book-linux-amd64_v1.0.1`, `index.html`, `main.jpeg`)은 **저장소에 없다** — 배부물이라
> git 에서 제외된다. 런북 시작 전에 `shared/provided/set-06-task-1/` 에 그대로 놓는다.
> `index.html`·`main.jpeg` 는 3단계 `s3.tf` 가 그 경로에서 직접 올리고, `book-linux-amd64_v1.0.1` 은
> 1단계가 S3 릴레이로 CloudShell 에 넘긴다.

## 배포 순서

> **머신 3분할** — ① **본 PC(PowerShell 7)**: `terraform apply`·`eksctl`·`kubectl`·`helm`·시드·정리.
> ② **일반 CloudShell**(VPC environment 아님): 컨테이너 이미지 작업 전부 — 대회 PC 는 Docker·WSL 을 못 쓴다.
> ③ **채점 CloudShell**: 자가 채점(`mark.sh`)만(mark.md 유의사항 14).
> 클러스터 엔드포인트가 public 이라 `kubectl`·`helm` 은 본 PC 에서 되고, set-07 과 달리 VPC environment 는 필요 없다.
> tfstate·`.terraform/` 은 어디에도 올리지 않는다.
> 작업용 bastion 은 두지 않는다 — 과제지가 요구하지 않는 EC2 는 불필요 리소스 감점 대상이다.

> **파일을 CloudShell 로 넘기는 법** — 텍스트(`Dockerfile`·환경변수)는 **붙여넣기**, 붙여넣을 수 없는
> 제공 바이너리만 **S3 릴레이**(`s3://gj2026-static-<비번호>/_transfer/`)로 넘긴다. 그래서 1단계가
> S3 버킷까지 먼저 만든다. 릴레이 접두어에는 `/` 가 들어가므로 **채점 6-1-A 출력에 잡히지 않지만**
> (`Contents[?contains(Key,'/')==false]`), 7단계에서 지운다.

> **병렬 실행** — 1단계가 끝나면 2단계(CloudShell)와 3단계(본 PC)는 서로 독립이라 동시에 돌릴 수 있다.
> 4단계(EKS 생성)만 2단계(bootstrap 이미지 push)와 3단계(terraform 출력값)가 **둘 다** 끝나야 시작된다.

### 0) [본 PC·PowerShell] 사전 변수 · 신원 확인

```powershell
cd set-06\task-1\terraform
$env:AWS_REGION = "ap-northeast-2"
$env:AWS_DEFAULT_REGION = "ap-northeast-2"
$env:NUM = "<선수등번호>"      # bibunho — S3 버킷 이름에 들어간다

# 본 PC 신원 = 채점 CloudShell 신원(지급 IAM 사용자)이어야 한다
aws sts get-caller-identity --query Arn --output text
```

> 본 PC 가 클러스터를 만들므로 `bootstrapClusterCreatorAdminPermissions` 에 따라 **본 PC 신원이 그대로
> 클러스터 admin** 이 된다. 채점 CloudShell 을 여는 IAM 사용자와 같아야 채점 셸에서 `kubectl` 이 된다.
> 액세스 키가 없으면 `aws login`(AWS CLI 2.32.0 이상)으로 콘솔 자격증명을 그대로 쓴다.
> 어긋났으면 8단계 각주의 access entry 로 사후 보정한다.

### 1) [본 PC·PowerShell] ECR·S3 선행 생성 + 제공 바이너리 릴레이

ECR 은 이미지 push 보다, S3 버킷은 릴레이보다 먼저 있어야 한다. 나머지는 3단계에서 만든다.

```powershell
terraform init
terraform apply -var "bibunho=$env:NUM" `
  -target="aws_ecr_repository.book" -target="aws_ecr_repository.direct" `
  -target="aws_ecr_pull_through_cache_rule.public" `
  -target="aws_s3_bucket.static"

$env:ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$env:ECR    = "$env:ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com"
$env:BUCKET = "gj2026-static-$env:NUM"

# 붙여넣을 수 없는 것만 릴레이로 넘긴다 (8.4MB 바이너리). 7단계에서 지운다.
aws s3 cp ..\..\..\shared\provided\set-06-task-1\book-linux-amd64_v1.0.1 `
  "s3://$env:BUCKET/_transfer/book-linux-amd64_v1.0.1"

"ACCOUNT_ID=$env:ACCOUNT_ID  BUCKET=$env:BUCKET"   # 2단계에 붙여넣을 값
```

> 이 시점의 버킷에는 아직 기본 암호화·버킷 정책이 없다(3단계에서 붙는다). 릴레이 객체는
> 채점 전에 지우고, 채점 대상인 루트 객체(`index.html`·`main.jpeg`)는 3단계 terraform 이 올린다.

### 2) [일반 CloudShell] 컨테이너 이미지 전부 (book 빌드 · 미러 · PTC 워밍업)

> 콘솔에서 **일반 CloudShell**(VPC environment 아님)을 연다 — Docker 와 인터넷 egress 가 둘 다 필요하다.
> 대회 PC 는 Docker·WSL 을 못 쓰므로 이미지 작업은 전부 여기서 한다. 끝나면 이 셸은 더 쓰지 않는다.
> **NAT 가 없어** 노드는 인터넷에 못 나간다 — 노드가 쓸 이미지는 전부 여기서 ECR 로 올려둬야 한다.

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR="$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com"
export BUCKET="gj2026-static-<비번호>"          # 1단계 출력값

aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR"
mkdir -p ~/book-image && cd ~/book-image
aws s3 cp "s3://$BUCKET/_transfer/book-linux-amd64_v1.0.1" .    # 제공 바이너리 (수정 금지)

# Dockerfile 은 텍스트라 붙여넣는다. 아래 첫 줄까지 실행 → app/Dockerfile 전문 붙여넣기 → DOCKEREOF 입력
cat > Dockerfile <<'DOCKEREOF'
# ← 본 PC 의 app/Dockerfile 전문을 그대로 붙여넣는다 (이 주석 줄은 지운다)
DOCKEREOF
wc -l Dockerfile      # 17 — 원본과 줄 수가 같아야 한다
```

**2-1) book 이미지 (채점 2-2 의 3MB 제한).** 제공 바이너리 8.4MB 는 zstd -19/-22 로도 3.07MB 라 초과한다.
`Dockerfile` 이 **UPX 로 바이너리를 선압축**한 뒤 zstd 로 밀어야 3MB 아래로 떨어진다.
원본 제공 파일은 무수정 — 빌드 단계에서만 압축한다.

```bash
# oci-mediatypes / force-compression 전부 필수 (NOTES.md §3.3). CloudShell 이 x86_64 라 --platform 불필요
docker buildx build --provenance=false \
  --output "type=image,name=$ECR/book:latest,oci-mediatypes=true,compression=zstd,compression-level=19,force-compression=true,push=true" \
  -f Dockerfile .

# 3145728(3MB) 이하여야 한다 — 넘으면 채점 2-2 가 0점이다
aws ecr describe-images --repository-name book \
  --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text
```

> `docker buildx` 가 없으면 `docker buildx version` 이 실패한다. 그 경우 zstd 출력이 안 되므로
> **3MB 를 못 맞춘다** — NOTES.md 「미검증」의 대체안을 본다.

**2-2) 노드가 쓸 이미지 — 미러 + PTC 워밍업.** CloudShell 디스크가 넉넉하지 않으니
**pull → tag → push → rmi** 로 하나씩 비우며 진행한다.

```bash
# bootstrap container — 노드 부팅 경로라 PTC 의존 금지, 직접 push 한 리포지토리를 쓴다
docker pull public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.3.4
docker tag  public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.3.4 "$ECR/gj2026/br-bootstrap:1.0.0"
docker push "$ECR/gj2026/br-bootstrap:1.0.0"
docker rmi  public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.3.4 "$ECR/gj2026/br-bootstrap:1.0.0"

# Grafana (Docker Hub 전용 → 미러)
docker pull grafana/grafana:13.1.0
docker tag  grafana/grafana:13.1.0 "$ECR/mirror/grafana:13.1.0"
docker push "$ECR/mirror/grafana:13.1.0"
docker rmi  grafana/grafana:13.1.0 "$ECR/mirror/grafana:13.1.0"

# LBC
docker pull public.ecr.aws/eks/aws-load-balancer-controller:v2.17.1
docker tag  public.ecr.aws/eks/aws-load-balancer-controller:v2.17.1 "$ECR/mirror/aws-load-balancer-controller:v2.17.1"
docker push "$ECR/mirror/aws-load-balancer-controller:v2.17.1"
docker rmi  public.ecr.aws/eks/aws-load-balancer-controller:v2.17.1 "$ECR/mirror/aws-load-balancer-controller:v2.17.1"

# PTC 캐시 워밍업 (nginx-test 4-5 대비, fluent-bit) — 캐시만 채우면 되므로 바로 지운다
docker pull "$ECR/ecr-public/nginx/nginx:latest"          && docker rmi "$ECR/ecr-public/nginx/nginx:latest"
docker pull "$ECR/ecr-public/aws-observability/aws-for-fluent-bit:3.4.8" && docker rmi "$ECR/ecr-public/aws-observability/aws-for-fluent-bit:3.4.8"

# 태그가 실제로 올라갔는지 확인 — 리포지토리만 있고 이미지가 없으면 노드가 조용히 부팅에 실패한다
aws ecr describe-images --repository-name gj2026/br-bootstrap --query 'imageDetails[].imageTags' --output text
aws ecr describe-images --repository-name mirror/grafana      --query 'imageDetails[].imageTags' --output text
```

> Docker Hub 익명 pull 은 레이트 리밋이 있다. `toomanyrequests` 가 나면 몇 분 뒤 재시도한다.
> 디스크가 모자라면 `docker system prune -af` 로 비우고 남은 것부터 이어서 한다.

### 3) [본 PC·PowerShell] 나머지 AWS 리소스 (CloudFront 배포 포함 — 최대 15분)

```powershell
terraform apply -var "bibunho=$env:NUM"
terraform output -json | Out-File outputs.json -Encoding utf8   # 본 PC 안에서만 쓴다

$out = terraform output -json | ConvertFrom-Json
$env:VPC_ID               = $out.vpc_id.value
$env:SUBNET_A_ID          = $out.private_subnet_ids.value[0]
$env:SUBNET_B_ID          = $out.private_subnet_ids.value[1]
$env:EKS_KMS_ARN          = $out.eks_kms_arn.value
$env:NODE_SHARED_SG_ID    = $out.node_shared_sg_id.value
$env:BOOK_POD_SG_ID       = $out.book_pod_sg_id.value
$env:BOOK_TG_ARN          = $out.book_tg_arn.value
$env:GRAFANA_TG_ARN       = $out.grafana_tg_arn.value
$env:BOOK_APP_POLICY_ARN  = $out.book_app_policy_arn.value
$env:GRAFANA_POLICY_ARN   = $out.grafana_policy_arn.value
$env:FLUENTBIT_POLICY_ARN = $out.fluentbit_policy_arn.value
$env:LBC_POLICY_ARN       = $out.lbc_policy_arn.value
$env:NODE_PTC_POLICY_ARN  = $out.node_ptc_policy_arn.value
$env:CF_DOMAIN            = $out.cloudfront_domain.value
$env:CF_DIST_ID           = $out.cloudfront_distribution_id.value
```

**`.env.ps1` 재작성** — 재접속·재부팅 대비(작업 규칙 6). 손으로 나열하지 않고 **키 목록에서 통째로
다시 쓴다.** 변수를 추가했는데 목록에 안 적어 조용히 빠지는 사고를 막는다. `.gitignore` 등록됨.

```powershell
$keep = @('AWS_REGION','AWS_DEFAULT_REGION','NUM','ACCOUNT_ID','ECR','BUCKET','VPC_ID',
          'SUBNET_A_ID','SUBNET_B_ID','EKS_KMS_ARN','NODE_SHARED_SG_ID','BOOK_POD_SG_ID',
          'BOOK_TG_ARN','GRAFANA_TG_ARN','BOOK_APP_POLICY_ARN','GRAFANA_POLICY_ARN',
          'FLUENTBIT_POLICY_ARN','LBC_POLICY_ARN','NODE_PTC_POLICY_ARN','CF_DOMAIN','CF_DIST_ID')

$missing = $keep | Where-Object { -not (Test-Path "env:$_") }
if ($missing) { throw "env 누락: $($missing -join ', ') — 위 블록을 다시 실행" }

$keep | ForEach-Object { "`$env:$_ = `"$((Get-Item "env:$_").Value)`"" } | Set-Content ..\.env.ps1
. ..\.env.ps1     # 새 터미널로 이어서 할 땐 task-1 에서 `. .\.env.ps1` 만 다시 실행
```

### 4) [본 PC·PowerShell] EKS 클러스터 + 인증 전환 + scale-up

노드명(채점 4-3)은 정규 노드그룹의 bootstrap container 가 `gj2026.<instance-id>.(addon|app).node` 로 바꾼다.
그런데 managed NG 가 자동 생성하는 access entry 의 username(`system:node:{{EC2PrivateDNSName}}`)이 커스텀
노드명과 불일치해 join 이 거부된다(실측). 그래서 **노드 0대로 생성 → 인증 전환 → scale-up** 순서를
반드시 지킨다.

manifest 의 `${VAR}` 를 렌더한다. **치환 전** 필요한 env 가 다 있는지 검사하고, **치환 후** 잔여 `${}` 가
없는지 검사한다 — 빈 값이 박힌 채로 클러스터가 만들어지면 20분 뒤에야 드러난다.

```powershell
cd ..\eksctl
. ..\.env.ps1     # 새 창이면 (task-1 에서)

# 미설정 변수를 빈 문자열로 삼키지 않고 즉시 던진다
function Expand-Tpl($Path) {
  [regex]::Replace((Get-Content -Raw $Path), '\$\{(\w+)\}',
    { param($m)
      $v = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
      if ($null -eq $v) { throw "환경 변수 미설정: $($m.Groups[1].Value)" }
      $v
    })
}

# bootstrap 스크립트 → base64 (CRLF 제거 필수 — Bottlerocket 에서 실행 실패 방지)
function B64-Script($Path) {
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(((Get-Content -Raw $Path) -replace "`r", "")))
}
$env:SET_HOSTNAME_ADDON_B64 = B64-Script bootstrap\set-hostname-addon.sh
$env:SET_HOSTNAME_APP_B64   = B64-Script bootstrap\set-hostname-app.sh

Remove-Item cluster.rendered.yaml -ErrorAction SilentlyContinue   # 이전 잔재로 검사를 통과하는 일이 없게
Expand-Tpl cluster.yaml | Out-File cluster.rendered.yaml -Encoding utf8

# 치환 후: 잔여 ${} 가 없어야 한다 (출력 없음 = 정상)
Select-String '\$\{' cluster.rendered.yaml

# --cfn-disable-rollback: 실패 시 스택·인스턴스를 남겨 디버깅 가능 (성공 시 영향 없음)
# 부트스트랩으로 설치한 eksctl 이 Windows 보안 설정에 막히면 스마트앱 컨트롤을 잠시 끈다
eksctl create cluster -f cluster.rendered.yaml --cfn-disable-rollback   # 약 15~20분

aws eks update-kubeconfig --name gj2026-eks-cluster
kubectl get nodes   # 아직 0개 (desired 0) — 정상
```

**인증 전환 후 scale-up — 순서를 바꾸지 않는다:**

```powershell
# 노드 role ARN (eksctl 생성 role — NG 마다 다르다)
$addonRole = aws eks describe-nodegroup --cluster-name gj2026-eks-cluster --nodegroup-name gj2026-eks-addon-nodegroup --query nodegroup.nodeRole --output text
$appRole   = aws eks describe-nodegroup --cluster-name gj2026-eks-cluster --nodegroup-name gj2026-eks-app-nodegroup   --query nodegroup.nodeRole --output text

# 1) 자동 생성된 EC2_LINUX access entry 삭제 — 남아 있으면 aws-auth 보다 우선해 join 을 거부한다
aws eks delete-access-entry --cluster-name gj2026-eks-cluster --principal-arn $addonRole
aws eks delete-access-entry --cluster-name gj2026-eks-cluster --principal-arn $appRole

# 2) eksctl 이 NG 생성 때 aws-auth 에 넣어둔 기본 매핑({{EC2PrivateDNSName}}) 제거 (중복되면 순서 불명 — 실측)
eksctl delete iamidentitymapping --cluster gj2026-eks-cluster --arn $addonRole --all
eksctl delete iamidentitymapping --cluster gj2026-eks-cluster --arn $appRole --all

# 3) aws-auth 매핑 — {{SessionName}} = 인스턴스 프로파일 세션명 = instance-id
#    → username 이 커스텀 노드명과 정확히 일치해 Node authorizer/NodeRestriction 정상 경로 유지
eksctl create iamidentitymapping --cluster gj2026-eks-cluster --arn $addonRole `
  --username "system:node:gj2026.{{SessionName}}.addon.node" --group system:bootstrappers --group system:nodes
eksctl create iamidentitymapping --cluster gj2026-eks-cluster --arn $appRole `
  --username "system:node:gj2026.{{SessionName}}.app.node" --group system:bootstrappers --group system:nodes

# 4) scale-up (채점 4-2: desired 2)
eksctl scale nodegroup --cluster gj2026-eks-cluster --name gj2026-eks-addon-nodegroup --nodes 2 --nodes-min 2
eksctl scale nodegroup --cluster gj2026-eks-cluster --name gj2026-eks-app-nodegroup   --nodes 2 --nodes-min 2

kubectl get nodes   # 2~5분 내 gj2026.i-xxxx.(addon|app).node 4개 Ready

# 채점 4-3 사전 검증 (mark.sh 와 같은 로직 — 4개가 전부 출력돼야 한다)
kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers | ForEach-Object {
  $id = $_.Split('.')[1]
  if ($id -like 'i-*') { $_ }
}

# 5) kubelet-serving CSR 수동 승인 (필수) — EKS 자동 승인기가 커스텀 노드명 CSR 을 승인하지 않는다.
#    방치하면 kubectl logs/exec 전멸 → metrics-server 미동작 + 채점 4-5(nginx-test exec) 실패.
#    노드 교체·재부팅 후 새 CSR 이 생기면 다시 승인한다.
kubectl get csr -o name | ForEach-Object { kubectl certificate approve $_ }
kubectl top nodes   # 1분 내 4개 노드 메트릭이 나오면 정상
```

> 노드그룹이 콘솔·`describe-nodegroup` 에서 `DEGRADED (AccessDenied)` 로 보이는 것은 **정상**이다 —
> MNG 서비스가 자기 access entry 를 찾는 것일 뿐, 노드 동작과 채점 4-2 출력(이름/amiType/타입/desired)에는
> 영향이 없다(실측 확인).
>
> join 이 안 되면(수 분 내 노드 미출현): `aws eks list-access-entries --cluster-name gj2026-eks-cluster` 에
> 노드 role 이 **없어야** 정상(남아 있으면 재삭제) → `eksctl get iamidentitymapping --cluster gj2026-eks-cluster`
> 로 username 오타 확인 → CloudWatch `authenticator` 로그에서 매핑 결과 확인.
> SSM 으로 kubelet 로그: `apiclient exec admin sheltie journalctl -u kubelet`.

### 5) [본 PC·PowerShell] Helm 애드온 + Kubernetes 리소스

```powershell
cd ..\k8s
. ..\.env.ps1   # 새 창이면 (task-1 에서)

# Pod SG 활성화 — SGP 의 전제이며 신규 Pod 부터 적용된다. 반드시 Pod 생성 전에 건다
kubectl set env daemonset aws-node -n kube-system ENABLE_POD_ENI=true

kubectl apply -f 00-namespace.yaml

# 6-1) LBC — TargetGroupBinding CRD 를 제공하므로 TGB 보다 먼저
helm repo add eks https://aws.github.io/eks-charts && helm repo update
Expand-Tpl lbc-values.yaml | Out-File lbc-values.rendered.yaml -Encoding utf8
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller `
  -n kube-system -f lbc-values.rendered.yaml

# 6-2) Grafana — release 이름을 정확히 `grafana` 로 고정한다. Service 명이 TGB serviceRef 와 일치해야 한다
helm repo add grafana-community https://grafana-community.github.io/helm-charts && helm repo update
Expand-Tpl monitoring\grafana-values.yaml | Out-File monitoring\grafana-values.rendered.yaml -Encoding utf8
helm upgrade --install grafana grafana-community/grafana -n monitoring -f monitoring\grafana-values.rendered.yaml

# 6-3) Fluent Bit — release 이름 = DaemonSet 이름 `aws-for-fluent-bit` (채점이 rollout restart 를 건다)
Expand-Tpl logging\fluent-bit-values.yaml | Out-File logging\fluent-bit-values.rendered.yaml -Encoding utf8
helm upgrade --install aws-for-fluent-bit eks/aws-for-fluent-bit -n logging -f logging\fluent-bit-values.rendered.yaml
```

manifest 는 파일별 `Expand-Tpl | kubectl apply` 대신 **`rendered/` 에 통째로 렌더한 뒤 폴더 하나를 apply** 한다.
파이프로 바로 넘기면 치환 결과가 남지 않아 무엇이 적용됐는지 사후에 확인할 수 없다.

```powershell
Remove-Item -Recurse -Force rendered -ErrorAction SilentlyContinue

# helm values 와 그 렌더 결과는 kubectl 대상이 아니므로 제외
$srcs = Get-ChildItem -Recurse -Filter *.yaml |
  Where-Object { $_.FullName -notmatch '\\rendered\\' -and $_.Name -notlike '*-values*.yaml' }

foreach ($f in $srcs) {
  $rel = Resolve-Path -Relative $f.FullName
  $dst = Join-Path 'rendered' $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Expand-Tpl $f.FullName | Out-File $dst -Encoding utf8      # 미설정 env 면 여기서 throw
}

# 치환 후: 잔여 ${} 가 없어야 한다 (출력 없음 = 정상)
Select-String -Path rendered\*  -Pattern '\$\{' -Recurse

kubectl apply -R -f rendered\      # 00-namespace 가 사전순 처음이라 ns 부터 적용된다

# 앱 타겟 healthy 대기
aws elbv2 wait target-in-service --target-group-arn $env:BOOK_TG_ARN
```

> `k8s/app/` 의 번호 prefix(`01-configmap` … `05-targetgroupbinding`)는 `apply -R` 사전순에서 ConfigMap 이
> Deployment 보다, SGP 가 TGB 보다 먼저 오게 하려는 것이다. 번호를 지우면 순서가 무너진다.

### 6) [본 PC·PowerShell] 데이터/트래픽 시드 (대시보드 데이터 확보)

PowerShell 의 `curl` 은 `Invoke-WebRequest` 별칭이므로 **반드시 `curl.exe`** 를 쓴다.

```powershell
. .\.env.ps1   # 새 창이면 (task-1 에서)
$CF = "https://$env:CF_DOMAIN"

curl.exe -s -o NUL -w "%{http_code} %header{x-cache}`n" $CF                # 200 Miss
curl.exe -s -o NUL -w "%{http_code} %header{x-cache}`n" "$CF/index.html"   # 2회째 200 Hit
curl.exe -sX POST -H "Content-Type: application/json" `
  -d '{\"client_id\":\"C001\",\"username\":\"Alice\",\"email\":\"kim@example.com\",\"concert_name\":\"Busan2025\"}' "$CF/v1/book"
curl.exe -s "$CF/reservation?client_id=C001"
curl.exe -s -w " %{http_code}`n" "$CF/v1/book"                        # 405 Method Not Allowed
curl.exe -s -w " %{http_code}`n" "$CF/reservation?client_id=123abc"   # 403 Access Denied
```

### 7) [본 PC·PowerShell] 채점 전 정리

> **필수**: `books` 테이블은 **비어 있어야** 한다. mark.sh 8-2 가 시드 2건(Alice/C001, Bob/C002)을 직접 넣고
> 8-3(전체 2건)·8-4(C001 1건)로 검증하므로, 잔여 데이터가 있으면 개수 불일치로 깨진다.
> 6단계 시드나 10-1 리허설로 POST 를 쐈다면 반드시 여기서 비운다. **(실측 감점 사례)**

```powershell
cd ..\terraform

# 쓰기 Deny 를 일시 해제해야 삭제가 된다
terraform apply -var "bibunho=$env:NUM" -var enable_ddb_write_deny=false

$ids = (aws dynamodb scan --table-name books --projection-expression booking_id `
        --query 'Items[].booking_id.S' --output text) -split "\s+"
foreach ($id in $ids) {
  aws dynamodb delete-item --table-name books --key "{\"booking_id\":{\"S\":\"$id\"}}"
}

terraform apply -var "bibunho=$env:NUM" -var enable_ddb_write_deny=true

# ★ Deny 전파 확인 (필수) — 재적용 직후엔 전파 지연이 있어 put-item 이 잠시 통과한다.
#   그 상태로 채점하면 3-3(AccessDenied 기대)이 깨지고, 통과된 put-item 이 테이블을 오염시켜 8-3 까지 깬다.
do {
  $r = aws dynamodb put-item --table-name books `
        --item '{\"booking_id\":{\"S\":\"deny-probe\"},\"client_id\":{\"S\":\"X\"}}' 2>&1
  if ("$r" -match "AccessDenied") { "Deny 활성 확인 — 채점 시작 가능"; break }
  aws dynamodb delete-item --table-name books --key '{\"booking_id\":{\"S\":\"deny-probe\"}}' 2>$null
  Start-Sleep 10
} while ($true)

# S3 릴레이 제거 — 1단계에서 올린 제공 바이너리. 채점 6-1-A 는 '/' 없는 키만 세지만 남길 이유가 없다
aws s3 rm "s3://$env:BUCKET/_transfer/" --recursive
aws s3api list-objects-v2 --bucket $env:BUCKET --query 'Contents[].Key' --output text   # index.html main.jpeg 만

# CloudFront 캐시 무효화
aws cloudfront create-invalidation --distribution-id $env:CF_DIST_ID --paths '/*'
$env:CF_DIST_ID    # 8단계 CloudShell 에 붙여넣을 값
```

### 8) [채점 CloudShell] 자가 채점

**모든 채점은 CloudShell 에서 한다**(mark.md 유의사항 14). `mark.sh` 는 CloudShell 최상위 경로에 둔다(유의사항 13).

```bash
# 사전 준비 — CloudShell 전용, 로컬에서 절대 실행하지 않는다 (~/.aws 삭제는 잔여 자격증명 청소용)
rm -rf ~/.aws

# mark.sh 안에서 선수가 직접 채워야 하는 placeholder
export DistributionID="<7단계에서 출력한 CF_DIST_ID>"
export BUCKET="gj2026-static-<비번호>"
export CF_DOMAIN=$(aws cloudfront get-distribution --id ${DistributionID} --query "Distribution.DomainName" --output text)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws configure set default.region ap-northeast-2

# 클러스터 접속 — 채점자가 쓸 것과 같은 한 줄이다
aws eks update-kubeconfig --name gj2026-eks-cluster
kubectl get nodes    # 4개가 보여야 한다

aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com

# CDN 캐시 무효화 (최대 3분) — 7단계에서 이미 했다면 생략 가능
export InvalidationID=$(aws cloudfront create-invalidation --distribution-id ${DistributionID} --paths "/*" --query "Invalidation.Id" --output text)
aws cloudfront wait invalidation-completed --distribution-id ${DistributionID} --id ${InvalidationID}

bash mark.sh
```

> `kubectl get nodes` 가 `Unauthorized` 면 0단계의 본 PC 신원이 이 셸과 달랐다는 뜻이다:
> `aws eks create-access-entry --cluster-name gj2026-eks-cluster --principal-arn <ARN>` →
> `aws eks associate-access-policy --cluster-name gj2026-eks-cluster --principal-arn <ARN> --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster`.
> 이미 엔트리가 있으면 `ResourceInUseException` 이 나며 무해하다 — associate 만 다시 실행한다.
> 컨텍스트 설정 오류면 **1회에 한해** `rm -rf ~/.kube/` 후 재실행할 수 있다(유의사항 19).

- 항목 순서대로 채점한다(유의사항 6). `(예상 출력)` 은 바로 위 `(명령어 입력)` 의 결과다(유의사항 11).
- 부분 점수 없는 항목은 전부 맞아야 인정된다(유의사항 9) — 배점표는 `mark.md`.
- **10-2 (Grafana, 수동 채점)**: mark.sh 실행 후 `${CF_DOMAIN}/grafana` 에 `admin`/`Skills53#` 로 접속해
  WSI Dashboard 의 Query Count Panel 에서 `ALL`·`C001` 두 시리즈가 8-3 실행 시각에 1개씩 찍혔는지
  육안 확인한다(최대 3분 대기).
- **삭제된 채점자료는 되돌릴 수 없다**(유의사항 7) — mark.sh 가 리소스를 변경·삭제하는 항목
  (4-5 nginx-test 재생성, 로그 그룹 삭제)이 있으니 재채점 전 상태를 미리 파악해 둔다.
- 출력이 기대와 다르면 아래 「문제 해결」 표 → `NOTES.md` 실측 함정 순으로 대조한다.

## 리소스 정리 (teardown)

destroy 를 막는 지점은 코드에 박혀 있다. 순서를 지키지 않으면 리소스가 남는다.

| 항목 | 근거 | 조치 |
|---|---|---|
| DynamoDB 쓰기 Deny | `var.enable_ddb_write_deny = true` | T1 에서 `false` 로 apply 후 비운다 |
| ECR 이미지 | 리포지토리에 이미지가 남으면 destroy 실패 | T2 에서 `force_delete` 확인, 아니면 이미지 먼저 삭제 |
| 노드그룹 드레인 | Bottlerocket NG 2개 | T3 에 `--disable-nodegroup-eviction` |
| CloudFront 배포 | disable → 삭제까지 15분 전후 | T4 destroy 가 오래 걸린다. 끊기면 같은 명령 재실행 |
| KMS 키 | `kms.tf` 예약 삭제 | destroy 후 예약 삭제로 넘어간다 (`cancel-key-deletion` 으로 취소 가능) |

k8s 가 Ingress·`type: LoadBalancer` 대신 TargetGroupBinding 을 쓰므로 LBC 가 만든 고아 ALB 는 없다.
ALB 는 terraform 소유라 T4 에서 정리된다.

### T1) [본 PC·PowerShell] DynamoDB 비우기

```powershell
cd set-06\task-1\terraform
. ..\.env.ps1
terraform apply -var "bibunho=$env:NUM" -var enable_ddb_write_deny=false
# 7단계의 scan → delete-item 루프를 그대로 다시 돌린다
```

### T2) [본 PC·PowerShell] ECR 이미지 삭제

```powershell
foreach ($r in @('book','gj2026/br-bootstrap','mirror/grafana','mirror/aws-load-balancer-controller')) {
  $ids = aws ecr list-images --repository-name $r --query 'imageIds[*]' --output json
  if ($ids -ne '[]') { aws ecr batch-delete-image --repository-name $r --image-ids "$ids" | Out-Null }
}
```

### T3) [본 PC·PowerShell] EKS 클러스터

```powershell
eksctl delete cluster -f ..\eksctl\cluster.rendered.yaml --disable-nodegroup-eviction --wait
```

### T4) [본 PC·PowerShell] terraform destroy

```powershell
terraform destroy -var "bibunho=$env:NUM"
```

> CloudFront 배포 disable→삭제에 15분 전후. 타임아웃으로 끊기면 같은 명령을 다시 돌린다.

### T5) [본 PC·PowerShell] 잔재 확인

```powershell
# 계정에 다른 세트 리소스가 섞여 있다. 반드시 이름·태그로 좁힌다
aws ec2 describe-vpcs --query "Vpcs[?Tags[?Key=='Name'&&Value=='gj2026-vpc']].VpcId" --output text
aws ec2 describe-volumes --filters "Name=tag-key,Values=kubernetes.io/cluster/gj2026-eks-cluster" `
  --query "Volumes[].[VolumeId,State,Size]" --output text
aws iam list-roles --query "Roles[?starts_with(RoleName,'gj2026')].RoleName" --output text
aws logs describe-log-groups --query "logGroups[?contains(logGroupName,'gj2026')||contains(logGroupName,'book-svc')].logGroupName" --output text
aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'gj2026')].LoadBalancerName" --output text
aws s3api list-buckets --query "Buckets[?starts_with(Name,'gj2026')].Name" --output text
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED `
  --query "StackSummaries[?contains(StackName,'gj2026')].[StackName,StackStatus]" --output text
```

> 전부 비어야 정리 완료다. CloudFormation 에 `DELETE_FAILED` 가 남으면 eksctl 이 못 지운 스택이 있다는 뜻이다.

---

## 요구사항 ↔ 구현 매핑

채점 항목 ID 는 `mark.sh`·`mark.md` 기준이다. 항목별 판정과 근거는 [NOTES.md 채점 커버리지](NOTES.md#채점-커버리지).

| 채점 | 내용 | 구현 |
|---|---|---|
| 1-1-A · 1-2-A · 1-3-A | VPC · Route Table · **NAT 없음** | `terraform/vpc.tf` |
| 2-1-A · 2-2-A | ECR 리포지토리 · 이미지 3MB 이하 | `terraform/ecr.tf`, `app/Dockerfile` |
| 3-1-A · 3-2-A · 3-3-A | DynamoDB 구성 · 암호화 · 쓰기 Deny | `terraform/dynamodb.tf`, `terraform/kms.tf` |
| 4-1-A · 4-2-A | EKS 1.35 · NodeGroup 2개 desired 2 (Bottlerocket) | `eksctl/cluster.yaml` |
| 4-3-A | 커스텀 노드명 `gj2026.<instance-id>.(addon\|app).node` | `eksctl/bootstrap/set-hostname-*.sh` + 4단계 인증 전환 |
| 4-4-A | Application Pods | `k8s/app/02-deployment.yaml` |
| 4-5-A | Network Policy (Pod SG) | `k8s/app/04-securitygrouppolicy.yaml`, `terraform/vpc.tf` book pod SG |
| 5-1-A | ALB `gj2026-alb` + TG 2종 | `terraform/alb.tf`, `k8s/app/05-targetgroupbinding.yaml`, `k8s/monitoring/grafana-tgb.yaml` |
| 6-1-A · 6-2-A | S3 객체 존재 · 암호화 | `terraform/s3.tf`, `terraform/kms.tf` |
| 7-1-A | Lambda `gj2026-book-reservation` | `terraform/lambda.tf`, `terraform/lambda/index.py` |
| 8-1-A | S3 정적 콘텐츠 (CloudFront 경유) | `terraform/cloudfront.tf` + `gj2026-rewrite-index` 함수 |
| 8-2-A | ALB API (`POST /v1/book`) | `app/Dockerfile`, `k8s/app/*` |
| 8-3-A · 8-4-A | Lambda 조회 API (전체 2건 · C001 1건) | `terraform/lambda/index.py` — **`books` 0건 상태에서 채점 시작** |
| 9-1-A · 9-2-A | WAF HTTP 메서드 제한 · 쿼리스트링 제한 | `terraform/waf.tf` 룰 `deny-non-post-on-api`·`deny-invalid-client-id` |
| 10-1-A | Fluent Bit → `/eks/book-svc/access` (스트림 정확히 2개) | `k8s/logging/fluent-bit-values.yaml` |
| 10-2-A | Grafana 대시보드 (**수동 채점**) | `k8s/monitoring/grafana-values.yaml`, `dashboard-configmap.yaml` |

## 검증 시드 / 채점 포인트

- 채점은 CloudShell 에서 `bash mark.sh` 일괄 실행(유의사항 14).
- 핵심 확인: `aws ecr describe-images`(imageSizeInBytes ≤ 3145728),
  `kubectl get nodes`(`gj2026.i-*.addon|app.node` 4개), `kubectl top nodes`(CSR 승인 완료 증거),
  CloudFront `/`·`/index.html`·`/v1/book`·`/reservation`·`/grafana` 5경로,
  WAF 차단 시 403, `books` 테이블 0건 상태에서 채점 시작, 로그 스트림 정확히 2개.
- Grafana 10-2 는 **육안 채점**이라 8-3 실행 시각에 `ALL`·`C001` 두 시리즈가 찍혀야 한다.

## 주의 / 검증 필요 포인트

- **인증 전환 순서가 이 세트의 최대 함정**이다. 노드 0대 생성 → access entry 삭제 → aws-auth 매핑 →
  scale-up. 순서를 바꾸면 노드가 join 하지 못하고, 증상은 "노드가 안 뜬다" 하나로만 보인다.
- **kubelet-serving CSR 수동 승인을 빠뜨리면** `kubectl logs/exec` 와 metrics-server 가 전멸하고
  채점 4-5 가 깨진다. 노드가 바뀔 때마다 다시 승인한다.
- **NAT 가 없다.** 노드가 인터넷에 못 나가므로 새 이미지를 쓰려면 2단계처럼 PTC/미러에 먼저 올린다.
  부팅 경로(br-bootstrap)는 PTC 에 의존하면 안 된다 — 리포지토리만 있고 태그가 없으면 부팅이 조용히 실패한다.
- **`books` 테이블은 채점 시작 시점에 반드시 0건**이어야 하고, 쓰기 Deny 는 **전파 확인까지** 끝나야 한다.
- **이미지 작업은 전부 일반 CloudShell 에서 한다**(2단계). 대회 PC 는 Docker·WSL 을 못 쓴다.
  이 경로 자체는 실측 검증되지 않았다 — 특히 CloudShell 의 `docker buildx` + zstd 출력 지원이 전제다
  (NOTES.md 「미검증」).
- **set-06 은 DAY-OF.md·KIT-INDEX.md·QUICK-REFERENCE.md·NAMING-AUDIT.md 에 등재돼 있지 않다.**
  당일 값 대조·KIT 부착·이름 판정에서 이 세트만 빠진다 — 위 「값 대조표」로 대신한다.

## 문제 해결

| 증상 | 원인 | 조치 |
|---|---|---|
| scale-up 후 노드가 안 뜸 / `kubectl get nodes` 0개 (4단계) | 인증 전환 전에 scale-up 했거나, EC2_LINUX access entry 잔존(aws-auth 보다 우선), 또는 iamidentitymapping username 오타 | `list-access-entries` 에서 노드 role 재삭제 → `eksctl get iamidentitymapping` 으로 username 확인 → 노드는 kubelet 이 재시도하므로 별도 조치 불필요, 안 되면 인스턴스 종료(ASG 재생성) |
| 노드명이 `ip-10-x-x-x...` 그대로 (4단계) | bootstrap container 미렌더(B64 환경 변수 미설정) 또는 이미지 pull 실패 | `cluster.rendered.yaml` 에 `bootstrap-containers` 블록·base64 값 존재 확인, 2단계 br-bootstrap push 여부 확인 |
| 인스턴스는 running 인데 join 시도조차 없음 | br-bootstrap 이미지 미존재 → essential bootstrap container 실패로 부팅 중단 (실측) | `aws ecr describe-images --repository-name gj2026/br-bootstrap` 로 **태그** 존재 확인(리포만 있으면 안 됨) → push 후 인스턴스 종료(ASG 재생성) |
| `kubectl top nodes`/`logs`/`exec` 가 TLS 에러, metrics-server 0/1 | kubelet-serving CSR Pending — EKS 자동 승인기가 커스텀 노드명 미승인 (실측) | `kubectl get csr` 확인 후 4단계 5)의 approve 재실행 |
| NG 생성·scale-up 자체가 실패 (네트워킹 의심) | VPC 엔드포인트/서브넷 문제와 인증 문제 분리 필요 | `canary-nodegroup.yaml`(bootstrap 블록 없는 최소 NG) 생성 — join 성공이면 네트워킹 정상, 원인은 인증/이름 경로 |
| nginx-test / fluent-bit Pod 가 `ImagePullBackOff` | PTC 캐시 워밍업(2단계) 을 건너뜀 | 2단계의 `docker pull $ECR/ecr-public/...` 두 줄 재실행 |
| book·grafana TargetGroupBinding 이 계속 `unhealthy` | SGP 의 ALB SG→Pod SG 8080 규칙 누락, 또는 `ENABLE_POD_ENI=true` 를 Pod 생성 **이전에** 안 걸었음 | `kubectl set env daemonset aws-node ...` 를 먼저 실행했는지 확인 후 Pod 재생성(rollout restart) |
| Grafana Service 가 안 보이거나 TGB 가 대상 못 찾음 | helm release 이름이 `grafana` 가 아님 — Service 명이 TGB `serviceRef` 와 어긋남 | release 이름을 정확히 `grafana` 로 고정 |
| `terraform apply` 가 WAF 리소스에서 리전 오류 | CLOUDFRONT scope Web ACL 은 반드시 `us-east-1` provider | WAF 리소스에 `provider = aws.use1` alias 지정 확인 |
| CF 경유 `/v1/book`·`/grafana` 만 504 (30초) | VPC Origin 트래픽의 소스 IP 는 CF POP 공인 대역 — ALB SG 의 VPC CIDR 허용으론 REJECT | ALB SG 에 `cloudfront.origin-facing` managed prefix list 인그레스 존재 확인 (`vpc.tf` 반영됨) |
| 8-2 가 500/504 로 앱에서 실패 | SGP 파드 DNS 차단(노드 SG 53 인그레스 누락) 또는 이미지 CA 부재 | node SG 인그레스에 book pod SG 발 53 규칙 확인 → book 파드 로그의 `x509` / `lookup ... i/o timeout` 구분 |
| 재배포 후 book 파드가 한 AZ 로 몰림 | 롤링 서지 중 스프레드 제약이 기존 파드를 카운트 | 몰린 쪽 파드 1개 `kubectl delete pod` — 제약이 반대 AZ 로 강제 |
| curl 결과가 이상하거나 `Invoke-WebRequest` 에러 | PowerShell 의 `curl` 은 `Invoke-WebRequest` 별칭 | 6단계처럼 반드시 `curl.exe` |
| DynamoDB `delete-item` 이 `AccessDeniedException` | `enable_ddb_write_deny=true` 상태에서 삭제 시도 (7단계 순서를 건너뜀) | `terraform apply -var enable_ddb_write_deny=false` 먼저 |

각 항목의 근본 원인 분석은 `NOTES.md` 해당 절을 본다.

### NodeCreationFailure 재시도 절차 (클러스터 재생성 금지 — 노드그룹만 다시)

`Instances failed to join the kubernetes cluster` 가 떠도 **컨트롤플레인·OIDC·addon 은 살아있다.**
클러스터를 지우고 처음부터 돌리면 20분+, 노드그룹만 재시도하면 5~7분이다.

```powershell
# 0) 인증 로그 켜기 — 노드 인스턴스가 삭제돼도 서버쪽 등록 시도 기록은 남는다
eksctl utils update-cluster-logging --cluster gj2026-eks-cluster --enable-types authenticator,api --approve

# 1) 실패한 노드그룹 스택 정리 (--cfn-disable-rollback 을 썼다면 수동 삭제 필수)
aws cloudformation delete-stack --stack-name eksctl-gj2026-eks-cluster-nodegroup-gj2026-eks-app-nodegroup
aws cloudformation delete-stack --stack-name eksctl-gj2026-eks-cluster-nodegroup-gj2026-eks-addon-nodegroup
aws cloudformation wait stack-delete-complete --stack-name eksctl-gj2026-eks-cluster-nodegroup-gj2026-eks-app-nodegroup

# 2) 카나리로 원인 분리 (~5분) — bootstrap 블록 없는 최소 노드그룹
eksctl create nodegroup -f canary-nodegroup.yaml
kubectl get nodes    # join 성공 → hostname-override(bootstrap) 가 원인 / 실패 → 네트워킹 문제
eksctl delete nodegroup -f canary-nodegroup.yaml --approve   # 확인 후 즉시 정리

# 3-a) 카나리 성공(= hostname-override 원인): NOTES.md §3.5.1 실측 기록·우회 절차 참고
# 3-b) 카나리 실패(= 네트워킹): 생성 도중(인스턴스 살아있는 동안) 두 번째 터미널에서 kubelet 로그 확보
aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=gj2026-eks-canary-nodegroup" `
  --query "Reservations[].Instances[].InstanceId" --output text
aws ssm start-session --target <i-xxxx> --document-name AWS-StartInteractiveCommand `
  --parameters '{\"command\":[\"apiclient exec admin sheltie journalctl -u kubelet --no-pager | tail -150\"]}'

# 서버쪽 인증 기록 (노드가 이미 삭제된 뒤에도 조회 가능)
aws logs filter-log-events --log-group-name /aws/eks/gj2026-eks-cluster/cluster `
  --log-stream-name-prefix authenticator --filter-pattern "node" --max-items 50
```

> managed 노드그룹 실패 시 EKS 가 CloudFormation rollback 과 무관하게 ASG 를 0으로 내려 인스턴스를 지운다.
> kubelet 로그는 **생성 진행 중에만** 잡을 수 있다 — 실패 통보를 기다리지 말고 인스턴스가 뜨는 즉시 SSM 으로 붙는다.
