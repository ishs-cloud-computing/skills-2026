# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 — Unicorn Tickets Solution Architecture

EKS 기반 콘서트 예약 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 구성한 결과물.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준(단, CloudFront/WAF 및 Platform KMS 레플리카는 `us-east-1`).
본 PC 단계는 **PowerShell 7** 기준이다 — 본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 쓴다
(CloudShell 단계는 공통).

> **대회 당일에는 [DAY-OF.md](../../DAY-OF.md) 를 먼저 연다.** 과제지는 종이로 배부되어 파일 대조가 안 되므로,
> 아래 값 대조표로 종이 과제지를 훑고 다른 값에 형광펜을 친 뒤 이 런북으로 들어온다.

## 값 대조표 (당일 종이 과제지 대조용)

| 축 | 준비본 값 | 다르면 고칠 곳 |
|---|---|---|
| 리전 | `ap-northeast-2` (CloudFront·WAF·KMS 레플리카는 `us-east-1`) | `terraform/variables.tf: region` |
| 비번호 | `<비번호>` | `variables.tf: player_number` |
| EKS 클러스터 | `unicorn-eks-cluster` · `1.35` | `variables.tf: cluster_name`·`cluster_version` |
| VPC CIDR | `10.97.0.0/16` | `variables.tf: vpc_cidr` |
| 서브넷 이름 | `unicorn-subnet-{pub,priv}-{a,b,c}` (AZ별 1개, 총 6개) | `variables.tf: subnets` |
| 노드 타입 | `t3.medium` | `variables.tf: node_instance_type` |
| 감사 Role External ID | `unicorn-audit-2026` | `variables.tf: audit_external_id_prefix` |
| Grafana 관리자 | 빈 값(주입) | `variables.tf: grafana_admin_user`·`grafana_admin_password` |
| WAF XSS 룰 | `variables.tf: waf_xss_rules` 목록 | 문항이 추가되면 이 목록에 추가 |

⚠ **이름 접두어 `unicorn` 은 tfvars 밖에도 있다.** `eksctl/cluster.yaml` 과 `k8s/**` 에 리터럴로 박혀 있으니 접두어가 바뀌면 같이 친다. IAM Role 이름은 과제지 지정값과 **정확히** 일치해야 한다.

## 디렉토리 구조

```
terraform/   # AWS 인프라 (VPC/Endpoint/FlowLog, KMS, S3, ECR, DynamoDB, Lambda, ALB, CloudFront, WAF, IAM)
  ├─ versions.tf variables.tf data.tf
  ├─ vpc.tf flowlog.tf endpoints.tf kms.tf
  ├─ s3.tf ecr.tf dynamodb.tf lambda.tf lambda/index.py
  ├─ alb.tf cloudfront.tf waf.tf cloudwatch.tf
  └─ iam.tf iam/lbc-policy.json security.tf outputs.tf
eksctl/cluster.yaml      # EKS 1.35, private, authMode=API, Pod Identity, 2 NodeGroup(app/addon)
k8s/
  ├─ 00-namespaces.yaml 01-storageclass.yaml
  ├─ app/         # SA, ConfigMap, Deployment(book), Service, PDB, TargetGroupBinding
  ├─ logging/     # Fluent Bit DaemonSet (logfmt → 5키 JSON 재구성)
  └─ monitoring/  # kube-prometheus-stack values, cloudwatch-exporter, grafana TGB, dashboard.json
app/Dockerfile           # Book App 컨테이너 (alpine + book). book 은 빌드 시 shared 에서 받아 쓴다
README.linux.md          # 본 PC 가 Linux 일 때의 step 0·1·3·6·8 명령 (나머지 단계 공통)
```

> 제공된 배포파일(`book`, `index.html`, `main.jpeg`)은 repo 공용 `shared/provided/task-1/` 에 있다.
> S3 정적 업로드(`s3.tf`)는 이 경로를 직접 읽고, App 이미지 빌드는 `book` 을 S3 릴레이로 CloudShell 에 넘긴다.

## 배포 순서

> **머신 3분할** — ① **본 PC(PowerShell 7)**: `terraform apply` + `eksctl create cluster` + 시드 + 정리.
> ② **일반 CloudShell**: 컨테이너 빌드/푸시 — 대회 PC 는 Docker·WSL 을 못 쓴다.
> ③ **`unicorn-mark` CloudShell(VPC environment)**: `helm`·`kubectl` 과 채점(유의사항 14).
> 텍스트(환경변수·Dockerfile)는 **붙여넣기**로, 못 붙여넣는 것(`k8s` 번들 tgz·`book` 바이너리)만
> **S3 릴레이**로 넘긴다 — CloudShell 은 업로드 UI 가 없지만 터미널 붙여넣기는 된다.
> tfstate·`.terraform/` 은 어디에도 올리지 않는다.
> 작업용 bastion 은 두지 않는다 — 과제지가 요구하지 않는 EC2 는 불필요 리소스 감점 대상이고,
> 유의사항 14 가 `unicorn-mark` CloudShell 을 이미 강제한다.

> **private cluster 인데 eksctl 이 본 PC 에서 되는 이유** — eksctl 은 fully-private 클러스터를
> public+private 엔드포인트로 만든 뒤 **모든 작업이 끝나면 public 을 끈다**(eksctl 공식 문서 Limitations).
> 따라서 생성만 VPC 밖에서 되고, 생성이 끝난 뒤의 `kubectl`·`helm` 은 VPC 안에서만 된다.
> **중단되면 public 이 켜진 채 남는다** — step 3 끝의 엔드포인트 확인이 채점 6-1-A 방어선이다.

### 0) [본 PC·PowerShell] 사전 변수 · 신원 확인

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-2"
$env:NUM = "<선수등번호>"     # ExternalId / Grafana 계정에 사용

# 본 PC 신원 = 채점 CloudShell 신원(지급 IAM 사용자)이어야 한다
aws sts get-caller-identity --query Arn --output text
```

> 본 PC 가 클러스터를 만들므로(step 3) `bootstrapClusterCreatorAdminPermissions: true` 에 따라
> **본 PC 신원이 그대로 클러스터 admin** 이 된다. 채점 CloudShell 을 여는 IAM 사용자와 같아야
> 채점 셸에서 `kubectl` 이 된다. 액세스 키가 없으면 `aws login`(AWS CLI 2.32.0 이상)으로
> 콘솔 자격증명을 그대로 쓴다. 어긋나도 step 7 에서 access entry 로 사후 보정된다.

### 1) [본 PC·PowerShell] Terraform (네트워크 + AWS 리소스)

```powershell
cd terraform
terraform init
terraform apply -var "player_number=$env:NUM"
terraform output -json | Set-Content ..\outputs.json   # 본 PC 안에서만 쓴다 (step 3 eksctl · 아래 .env 블록)

$o = Get-Content ..\outputs.json | ConvertFrom-Json
$env:ACCOUNT_ID = $o.account_id.value
$env:BUCKET     = $o.s3_bucket_name.value

# 재접속 대비 (작업 규칙 6, .gitignore 등록됨). 새 창에선 task-1 에서 `. .\.env.ps1` 만 다시 실행
@"
`$env:AWS_DEFAULT_REGION = "ap-northeast-2"
`$env:NUM                = "$env:NUM"
`$env:ACCOUNT_ID         = "$env:ACCOUNT_ID"
`$env:BUCKET             = "$env:BUCKET"
"@ | Set-Content ..\.env.ps1

# CloudShell 은 파일 업로드 UI 가 없고(VPC environment 는 Actions 업로드 자체가 막혀 있다)
# 레포가 비공개라 git clone 도 불가 → 붙여넣을 수 없는 것만 S3 릴레이로 넘긴다.
# _transfer/ 는 채점 직전 step 8 에서 비운다 (web 버킷은 채점 대상 — mark.sh 3-1-A).
tar czf "..\task.tgz" -C .. k8s mark-2026-08-10.sh   # 2026-08-10 정정본. mark.sh 최초본은 대조용
aws s3 cp "..\task.tgz" "s3://$env:BUCKET/_transfer/task.tgz"
aws s3 cp ..\..\..\shared\provided\task-1\book "s3://$env:BUCKET/_transfer/book"   # 8.7MB 바이너리
```

**step 4 에 붙여넣을 `.env` 블록 출력** — 텍스트는 S3 를 태우지 않는다.

```powershell
# 값이 여기서 확정돼 박히므로 CloudShell 에 outputs.json 도 jq 도 필요 없다.
$cs = @"
cat > ~/.env <<'ENVEOF'
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=$env:NUM
export ACCOUNT_ID=$($o.account_id.value)
export VPC_ID=$($o.vpc_id.value)
export PLATFORM_KMS_ARN=$($o.platform_kms_arn.value)
export ECR=$($o.ecr_repository_url.value)
export APP_TG=$($o.app_target_group_arn.value)
export GRAFANA_TG=$($o.grafana_target_group_arn.value)
export GRAFANA_USER=skills$env:NUM
export GRAFANA_PW='HelloKrSkills!'$env:NUM'@'
ENVEOF
sed -i 's/\r`$//' ~/.env
"@
$cs                     # 콘솔 출력 — 이걸 복사해 step 4 에 붙여넣는다
# $cs | Set-Clipboard   # 바로 클립보드로 넣고 싶으면 이 줄을 쓴다
```

> 출력된 블록을 그대로 step 4 에 붙여넣는다. 우변이 빈 줄(`export VPC_ID=`)이 있으면 outputs.json 이
> 덜 만들어진 것이니 `terraform apply` 부터 다시 본다.
> 마지막 `sed` 는 **Windows 클립보드가 붙이는 CRLF 가드**다 — `\r` 이 값 끝에 남으면 ECR 태그나 ARN 이
> 조용히 어긋난다. 멱등하므로 여러 번 실행해도 무해하다.
> 세션이 끊겨 블록을 잃으면 이 PowerShell 블록만 다시 실행하면 된다(작업 규칙 6).

> Pod Identity 역할·SG·VPC Endpoint 는 Terraform 이 먼저 만들어야 eksctl 이 참조하므로 1) 을 가장 먼저 끝낸다.
> `eksctl/` 은 릴레이에 넣지 않는다 — 본 PC 에서만 쓴다.

### 2) [일반 CloudShell] 컨테이너 이미지 빌드 & ECR push (v1.0.0 + latest)

> 콘솔에서 **일반 CloudShell**(VPC environment 아님)을 연다 — Docker 와 인터넷 egress 가 둘 다 필요하다.
> 대회 PC 는 Docker·WSL 을 못 쓰므로 빌드는 여기서 한다. 끝나면 이 셸은 더 쓰지 않는다.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
mkdir -p ~/book-image && cd ~/book-image
aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/book" .     # 제공 바이너리 (수정 금지)

# Dockerfile 은 텍스트라 붙여넣는다. 아래 첫 줄까지 실행 → app/Dockerfile 전문 붙여넣기 → DOCKEREOF 입력
cat > Dockerfile <<'DOCKEREOF'
# ← 본 PC 의 app/Dockerfile 전문을 그대로 붙여넣는다 (이 주석 줄은 지운다)
DOCKEREOF
wc -l Dockerfile      # 22 — 원본과 줄 수가 같아야 한다

ECR=$(aws ecr describe-repositories --repository-names unicorn-concert-app \
  --query 'repositories[0].repositoryUri' --output text)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" -t "$ECR:latest" .    # CloudShell 이 x86_64 라 --platform 불필요
docker push "$ECR:v1.0.0" && docker push "$ECR:latest"

# scan 완료/취약점 0 확인 (요구사항 7)
aws ecr wait image-scan-complete --repository-name unicorn-concert-app --image-id imageTag=v1.0.0 || \
  { aws ecr start-image-scan --repository-name unicorn-concert-app --image-id imageTag=v1.0.0; \
    aws ecr wait image-scan-complete --repository-name unicorn-concert-app --image-id imageTag=v1.0.0; }
aws ecr describe-image-scan-findings --repository-name unicorn-concert-app --image-id imageTag=v1.0.0 \
  --query 'imageScanFindings.findingSeverityCounts'   # null/빈 값이어야 함
```

### 3) [본 PC·PowerShell] EKS 클러스터 (eksctl)

manifest 의 `${VAR}` 를 렌더한다. **치환 전** 필요한 env 가 다 있는지 검사하고, **치환 후** 잔여 `${}` 가
없는지 검사한다 — 빈 값이 박힌 채로 클러스터가 만들어지면 채점 때야 드러난다.

```powershell
cd ..\eksctl      # cwd = terraform 이었을 때. outputs.json 은 ..\outputs.json
. ..\.env.ps1     # 새 창이면 (task-1 에서)

$o = Get-Content ..\outputs.json | ConvertFrom-Json
$env:VPC_ID              = $o.vpc_id.value
$env:CP_EXTRA_SG_ID      = $o.eks_cp_extra_sg_id.value
$env:NODE_SHARED_SG_ID   = $o.eks_shared_node_sg_id.value
$env:PRIV_SUBNET_A       = $o.private_subnet_ids.value.'unicorn-subnet-priv-a'
$env:PRIV_SUBNET_B       = $o.private_subnet_ids.value.'unicorn-subnet-priv-b'
$env:PRIV_SUBNET_C       = $o.private_subnet_ids.value.'unicorn-subnet-priv-c'
$env:PLATFORM_KMS_ARN    = $o.platform_kms_arn.value
$env:BOOK_APP_ROLE_ARN   = $o.pod_identity_role_arns.value.book_app
$env:LBC_ROLE_ARN        = $o.pod_identity_role_arns.value.lbc
$env:FLUENTBIT_ROLE_ARN  = $o.pod_identity_role_arns.value.fluentbit
$env:CWEXPORTER_ROLE_ARN = $o.pod_identity_role_arns.value.cwexporter
$env:EBS_CSI_ROLE_ARN    = $o.pod_identity_role_arns.value.ebs_csi
$env:CF                  = $o.cloudfront_domain.value   # step 6 시드용

Remove-Item cluster.rendered.yaml -ErrorAction SilentlyContinue   # 이전 실행 잔재로 검사를 통과하는 일이 없게
$c = Get-Content cluster.yaml -Raw

# 치환 전: cluster.yaml 이 요구하는 env 가 전부 등록됐는지 검사.
# 검사 없이 치환하면 누락된 env 가 빈 문자열로 조용히 들어가고 20분 뒤 create 가 깨진다.
$vars = [regex]::Matches($c, '\$\{(\w+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$missing = $vars | Where-Object { -not (Test-Path "env:$_") }
if ($missing) { throw "env 누락: $($missing -join ', ') — 위 블록을 다시 실행" }

$vars | ForEach-Object { $c = $c.Replace('${' + $_ + '}', (Get-Item "env:$_").Value) }
$c | Set-Content cluster.rendered.yaml

# 치환 후: 잔여 ${} 가 없어야 함 (출력 없음 = 정상)
Select-String '\$\{' cluster.rendered.yaml

# 셸 재시작 대비 — .env.ps1 통째로 재작성 (덮어쓰기라 중복 누적 없음, 작업 규칙 6)
$keep = @('AWS_DEFAULT_REGION','NUM','ACCOUNT_ID','BUCKET','CF') + $vars
$keep | ForEach-Object { "`$env:$_ = `"$((Get-Item "env:$_").Value)`"" } | Set-Content ..\.env.ps1

eksctl create cluster -f cluster.rendered.yaml     # 약 20분. 완료 시 자동 private 전환
```

**엔드포인트 확인 — 이 단계를 건너뛰지 않는다:**

```powershell
aws eks describe-cluster --name unicorn-eks-cluster `
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,endpointPrivateAccess]'   # false, true 여야 함

# true 로 남았으면 (eksctl 이 중간에 끊긴 경우):
# aws eks update-cluster-config --name unicorn-eks-cluster --resources-vpc-config endpointPublicAccess=false
```

> 이 시점부터 본 PC 는 클러스터 API 에 못 붙는다. `kubectl get nodes` 가 타임아웃 나는 게 정상이며,
> public 이 꺼졌다는 증거다. 이후 k8s 작업은 전부 step 4 의 CloudShell 에서 한다.
> addon 버전은 `eksctl utils describe-addon-versions --kubernetes-version 1.35 --name <addon>` 로 확인 후 cluster.yaml 에 고정한다.
>
> **eksctl 이 본 PC 에서 실패하면** — step 4 의 CloudShell 에서 eksctl 을 설치하고
> `eksctl create cluster -f cluster.rendered.yaml --without-nodegroup` → `eksctl create nodegroup -f cluster.rendered.yaml`
> 로 쪼갠다(각 단계가 CloudShell 유휴 타임아웃 아래로 떨어진다). eksctl 은 CloudFormation 기반이라
> 끊겨도 같은 명령 재실행으로 수렴한다. `cluster.rendered.yaml` 은 S3 릴레이로 넘긴다.

### 4) [`unicorn-mark` CloudShell] 환경 생성 + 부트스트랩

> 채점은 반드시 `unicorn-mark` CloudShell 에서 한다(유의사항 14). 작업도 같은 셸에서 해
> 채점 경로를 배포 내내 검증한다. kubectl 은 CloudShell 기본 제공, helm 만 설치한다.

1. 콘솔 CloudShell → **Actions → Create VPC environment** → Name `unicorn-mark`, VPC `unicorn-vpc`,
   Subnet `unicorn-subnet-priv-a`, SG `unicorn-mark-sg`.
2. 부트스트랩:

```bash
# VPC environment 는 홈이 비영구다 — 20~30분 유휴로 세션이 끊기면 $HOME 이 지워진다.
# 그때는 이 step 4 전체(아래 블록 + .env 붙여넣기)를 다시 하면 복구된다 (작업 규칙 6).
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
mkdir -p ~/unicorn && cd ~/unicorn
aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/task.tgz" . && tar xzf task.tgz
cp mark-2026-08-10.sh ~/                                  # /home/cloudshell-user (유의사항 13)
```

**여기서 step 1 이 출력한 `.env` 블록을 붙여넣는다** — `cat > ~/.env <<'ENVEOF'` 로 시작해
`sed -i 's/\r$//' ~/.env` 로 끝나는 그 블록이다. 변수명은 k8s manifest·helm values 의 `${VAR}` 자리와
정확히 일치한다.

```bash
grep -c $'\r' ~/.env     # 0 이어야 한다 (CRLF 가 남았으면 위 sed 를 다시)
grep -qxF 'source ~/.env' ~/.bashrc || echo 'source ~/.env' >> ~/.bashrc
source ~/.env
echo "$VPC_ID $APP_TG $GRAFANA_USER"   # 값이 다 채워졌는지 눈으로 확인

# 클러스터 접속 — 채점자가 쓸 것과 같은 한 줄이다
aws eks update-kubeconfig --name unicorn-eks-cluster --region ap-northeast-2
kubectl get nodes    # 노드가 보여야 한다
```

> `kubectl get nodes` 가 안 되면 여기서 잡는다. 컨텍스트 설정에서 오류가 나면 **1회에 한해**
> `rm -rf ~/.kube/` 로 초기화한 뒤 다시 실행할 수 있다(유의사항 19) — kubeconfig 에 cluster info 가
> 이미 있으면 덮어쓰지 않는 동작이 원인이다. 권한 오류(`Unauthorized`)면 step 0 의 본 PC 신원이
> 이 셸과 달랐다는 뜻이므로 access entry 를 추가한다:
> `aws eks create-access-entry --cluster-name unicorn-eks-cluster --principal-arn <ARN>` →
> `aws eks associate-access-policy --cluster-name unicorn-eks-cluster --principal-arn <ARN> --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster`
> 이미 엔트리가 있으면 `ResourceInUseException` 이 나며 무해하다 — associate 만 다시 실행한다.

### 5) [`unicorn-mark` CloudShell] Helm 애드온 + Kubernetes 리소스

```bash
cd ~/unicorn/k8s

# 5-1) AWS Load Balancer Controller (SA 는 Pod Identity 로 권한 획득)
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.13.4 -n kube-system \
  --set clusterName=unicorn-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 --set vpcId="$VPC_ID" \
  --set nodeSelector.unicorn=addon

# 5-2) kube-prometheus-stack (release: unicorn-monitoring). 차트 버전 고정(작업규칙 2).
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update

# Grafana 계정 렌더 — helm values 라 kubectl 대상이 아니어서 따로 렌더
src=monitoring/kube-prometheus-stack-values.yaml
rm -f kps-values.rendered.yaml
missing=$(for v in $(grep -oh '[$]{[A-Za-z_][A-Za-z_0-9]*}' $src | tr -d '${}' | sort -u); do
  [ -z "${!v}" ] && echo "$v"; done)

if [ -n "$missing" ]; then
  echo "env 누락: $missing — step 4 의 ~/.env 를 다시 source"
else
  python3 -c 'import os,sys;sys.stdout.write(os.path.expandvars(sys.stdin.read()))' \
    < $src > kps-values.rendered.yaml
  grep -n '\${' kps-values.rendered.yaml && echo '치환 누락!' || echo OK
fi

helm upgrade --install unicorn-monitoring prometheus-community/kube-prometheus-stack \
  --version 87.2.1 -n monitoring --create-namespace -f kps-values.rendered.yaml

# 5-3) CloudWatch Exporter (ALB TargetResponseTime → Prometheus). placeholder 없음 — 원본 그대로 쓴다.
helm upgrade --install cloudwatch-exporter prometheus-community/prometheus-cloudwatch-exporter \
  --version 0.28.1 -n monitoring -f monitoring/cloudwatch-exporter-values.yaml
```

모든 manifest 를 `rendered/` 에 렌더한 뒤 폴더 하나를 apply 한다. 파일별 `sed | kubectl apply` 는 치환 누락을
조용히 통과시키므로, 렌더 결과를 파일로 남겨 검사한 다음 적용한다.

```bash
cd ~/unicorn/k8s
rm -rf rendered

# helm values(5-2)와 그 렌더 결과(kps-values.rendered.yaml)는 kubectl 대상이 아니므로 제외
srcs=$(find . -path ./rendered -prune -o -name '*.yaml' ! -name '*-values.yaml' ! -name '*.rendered.yaml' -print)

# 치환 전: manifest 전체가 요구하는 env 가 선언됐는지 검사
missing=$(for v in $(grep -oh '[$]{[A-Za-z_][A-Za-z_0-9]*}' $srcs | tr -d '${}' | sort -u); do
  [ -z "${!v}" ] && echo "$v"; done)

if [ -n "$missing" ]; then
  echo "env 누락: $missing — step 4 의 ~/.env 를 다시 source"
else
  # 렌더: k8s/ 하위 구조 그대로 rendered/ 에 미러
  for f in $srcs; do
    mkdir -p "rendered/$(dirname "$f")"
    python3 -c 'import os,sys;sys.stdout.write(os.path.expandvars(sys.stdin.read()))' < "$f" > "rendered/$f"
  done
  # 치환 후: 잔여 ${} 가 없어야 함
  grep -rn '\${' rendered/ && echo '치환 누락!' || echo OK
fi

# 위에서 OK 가 나왔을 때만 진행 (렌더 실패 시 rendered/ 가 없어 kubectl 이 바로 멈춘다)
kubectl apply -R -f rendered/   # 00-namespaces 가 사전순 처음이라 ns 부터 적용됨

# Grafana 대시보드(sidecar 가 label 로 자동 import). --from-file 이라 렌더 대상이 아니다.
kubectl create configmap unicorn-grafana-dashboard -n monitoring \
  --from-file=dashboard.json=monitoring/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap unicorn-grafana-dashboard -n monitoring grafana_dashboard=1 --overwrite

# 앱 타겟 healthy 대기
aws elbv2 wait target-in-service --target-group-arn "$APP_TG"
```

> `app/00-serviceaccount.yaml` 의 번호 prefix 는 `apply -R` 사전순에서 SA 가 Deployment 보다 먼저 오게 하려는 것이다.
> grafana TGB 는 5-2 helm 이 Grafana Service 를 이미 만든 뒤라 바로 바인딩된다.

### 6) [본 PC·PowerShell] 데이터/트래픽 시드 (대시보드 데이터 확보)

> CloudFront 는 공개라 VPC 밖에서 친다. 여기서부터 VPC 셸로 돌아갈 일이 없다.

```powershell
. .\.env.ps1   # 새 창이면 (task-1 에서)

$body = '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2025"}'
Invoke-RestMethod -Uri "https://$env:CF/v1/book" -Method Post -ContentType 'application/json' -Body $body   # booking_id 반환
1..20 | ForEach-Object { Invoke-WebRequest -Uri "https://$env:CF/health" -UseBasicParsing | Out-Null }       # ALB 메트릭 생성
```

### 7) [`unicorn-mark` CloudShell] 자가 채점

```bash
source ~/.env
bash ~/mark-2026-08-10.sh    # 2026-08-10 정정본
```

> 홈이 초기화된 뒤라면 step 4 부트스트랩 블록을 먼저 다시 실행한다.

### 8) [본 PC·PowerShell] 채점 전 정리

> 자가 채점을 통과한 뒤 **채점 직전**에 실행한다. `_transfer/` 를 지우면 step 4 부트스트랩 재료가
> 사라지므로 순서를 앞당기지 않는다.

```powershell
. .\.env.ps1   # 새 창이면 (task-1 에서)

# S3 릴레이 제거 (web 버킷은 채점 대상 — mark.sh 3-1-A)
aws s3 rm "s3://$env:BUCKET/_transfer/" --recursive
aws s3api list-objects-v2 --bucket "$env:BUCKET" --prefix _transfer/ --query 'Contents[].Key'  # null 확인
```

> (유의사항 9) 실행 중 부하/테스트 없어야 함 — 6) 시드는 one-shot. DynamoDB seed item 은 채점이 자체 `booking_id` 로 조회하므로 무방.


## 리소스 정리 유의사항

- DynamoDB 테이블의 리소스 삭제 보호 해제
- S3 비우기 (S3 버전 관리 관련 리소스 존재)

해당 작업을 진행하지 않고 `terraform destroy` 실행 시 리소스가 완전히 삭제되지 않습니다.

`eksctl delete cluster` 는 fully-private 클러스터라 API 에 못 붙어 실패할 수 있다 — `--force` 로 진행한다.


---

## 요구사항 ↔ 구현 매핑

| # | 요구사항 | 구현 |
|---|---------|------|
| 3 | Networking (10.97.0.0/16, pub/priv 3AZ, NAT, Flow Log, Endpoint) | `vpc.tf`, `flowlog.tf`, `endpoints.tf` |
| 4 | KMS 3키(app/data/platform-MRK), 90일 회전 | `kms.tf` |
| 5 | S3 `unicorn-web-<ACCOUNT_ID>` 차단/버전/Data CMK | `s3.tf` |
| 6 | DynamoDB `unicorn-concert-db` PK booking_id + GSI + PITR/삭제방지 | `dynamodb.tf` |
| 7 | ECR `unicorn-concert-app` IMMUTABLE_WITH_EXCLUSION, 스캔, Data CMK | `ecr.tf` + `app/Dockerfile` |
| 8 | EKS 1.35 private, authMode=API, Pod Identity, 2 NG, KST, 로그/EBS/Secret=Platform CMK | `eksctl/cluster.yaml`, `iam.tf`, `cloudwatch.tf` |
| 8 | App 워크로드(unicorn-book-app-deploy/book/svc, probe, graceful) | `k8s/app/*` |
| 9 | Lambda `unicorn-get-booking-func` (GET by booking_id, Platform CMK) | `lambda.tf` + `lambda/index.py` |
| 10-1 | ALB `unicorn-alb`(internal, GET→Lambda/POST·health→App, `unicorn-tg`) | `alb.tf` |
| 10-2 | CloudFront `unicorn-svc-cf` (s3-origin OAC + app-origin VPC Origin) | `cloudfront.tf`, `s3.tf` |
| 10-3 | WAF `unicorn-waf` (managed + rate-limit 50/60s + 로그) | `waf.tf` |
| 11 | Audit Role `unicorn-audit-role` (ExternalId/세션/최소권한) | `iam.tf` |
| 12 | Fluent Bit(5키 JSON, /health 제외) + Prometheus(SM 0) + Grafana | `k8s/logging/*`, `k8s/monitoring/*` |
| 13 | Book App(POST 저장, env, /health) | `app/`, `k8s/app/configmap.yaml` |

## 검증 시드 / 채점 포인트

- 채점은 `unicorn-mark` CloudShell 에서 `bash mark-2026-08-10.sh` (2026-08-10 정정본) 로 일괄 실행.
- 핵심 확인: `aws kms get-key-rotation-status`(app/data/platform = True 90), `aws ecr describe-repositories`(IMMUTABLE_WITH_EXCLUSION),
  `kubectl get nodes -l unicorn=app`(2 AZ 이상), `aws eks list-pod-identity-associations`(unicorn-book-app-sa),
  CloudWatch `/unicorn/eks/book-app` 로그 키 = `client_ip,method,path,status_code,timestamp`,
  WAF rate-limit 차단 시 `403 Request blocked by Unicorn WAF`, Grafana `unicorn-grafana-dashboard` 5패널 No Data 없음.

## 주의 / 검증 필요 포인트

- **eksctl 이 public 엔드포인트를 잠깐 연다**: fully-private 클러스터는 public+private 로 생성된 뒤
  마지막에 public 이 꺼진다. 중단되면 켜진 채 남고 그건 채점 6-1-A 0점이다 — step 3 끝의
  `describe-cluster` 확인을 반드시 거친다.
- **자격증명 신원**: 채점은 **PowerUser~Administrator 수준 IAM 사용자**의 CloudShell 에서 한다(2026-08-04 답변).
  본 PC 가 클러스터를 만들므로 본 PC 신원이 그 IAM 사용자와 같아야 한다.
  어긋나도 **access entry 로 사후 보정이 된다**(step 4 각주) — 신원이 IAM 사용자이기 때문이다.
- **CloudShell VPC environment 제약**: 홈이 비영구(20~30분 유휴 시 `$HOME` 삭제), Actions 업로드/다운로드
  불가, IAM 주체당 2개. 그래서 파일은 S3 릴레이로 넘기고 step 4 부트스트랩을 재실행 가능한 한 블록으로 둔다.
  인터넷은 private 서브넷 + NAT 조합이라 열려 있다(helm repo 접근).
- **Platform KMS = MRK**: 프라이머리(ap-northeast-2)·레플리카(us-east-1) 동일 키 자료. EKS/EBS/Log(서울)=프라이머리,
  WAF 로그(us-east-1)=레플리카. `alias/unicorn-kms-platform` 은 양 리전에 존재. 회전(90일)은 프라이머리가 관리.
- **이미지 풀**: private 서브넷에 NAT 가 있어 공개 레지스트리(LBC/Prometheus/Grafana/Fluent Bit)는 직접 pull.
  App 이미지(ECR)·로그(CloudWatch)는 VPC Endpoint(private DNS)로 인터넷 미경유.
- **Grafana 패널5(HTTP Request Duration)**: ALB TargetResponseTime 기반이라 트래픽이 있어야 데이터 표시 → 6) 시드 수행.
- **EKS Control Plane 로그 그룹**: eksctl 생성 전 Terraform 이 `/aws/eks/<cluster>/cluster` 를 Platform CMK 로 선생성.
