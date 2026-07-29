---
title: 배포 런북
description: set-03 1과제 인프라를 위→아래로 실행하는 순수 명령 런북 (PowerShell 7 기준)
sidebar:
  order: 2
---

EKS 기반 콘서트 예약(Book) 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 배포한다.
위→아래로 그대로 실행한다. 본 PC 가 Linux 면 저장소 `set-03/task-1/README.linux.md` 를 쓴다
(bastion·CloudShell 단계는 공통).

클러스터가 fully private 라 본 PC 에서 kubectl 이 닿지 않는다. 작업은 셋으로 나뉜다:
**본 PC·PowerShell**(terraform·eksctl) · **bastion**(SSM 접속, k8s·helm·검증) ·
**VPC CloudShell**(제출 전 mark.sh 1회 — 채점자와 같은 경로).

## 디렉토리 구조

```
terraform/   # AWS 인프라 (VPC, KMS×5, DynamoDB, ECR, S3, Lambda, CloudFront, WAF, IAM)
  ├─ providers.tf variables.tf terraform.tfvars data.tf
  ├─ vpc.tf security.tf endpoints.tf kms.tf
  ├─ dynamodb.tf ecr.tf s3.tf lambda.tf lambda/index.py
  ├─ cloudfront.tf waf.tf cloudwatch.tf
  ├─ bastion.tf bastion_user_data.sh   # 작업용 bastion (채점 대상 아님, step 9-3 에서 제거)
  └─ iam.tf iam/lbc-policy.json outputs.tf
eksctl/cluster.yaml      # EKS 1.35 fully private, authMode=API, Pod Identity, NG 2개(addon/workload)
k8s/
  ├─ 00-namespaces.yaml 01-coredns-wsc2026.yaml   # ns + 내부 도메인(wsc2026.skills.local) 패치
  ├─ app/         # SA, ConfigMap(book-config), Deployment, Service, PDB, Ingress(ALB)
  ├─ logging/     # Fluent Bit DaemonSet (logfmt → Reference02 JSON + log_to_metrics)
  ├─ monitoring/  # kube-prometheus-stack values, PrometheusRule 6종, dashboard.json
  └─ rendered/    # step 5 가 생성. 치환 결과 미러 — kubectl apply -R 대상 (gitignore)
app/                     # 배포파일 위치(book·index.html·main.jpeg) + Dockerfile. step 0 에서 복사
README.linux.md          # 본 PC 가 Linux 일 때의 step 0·1·3·7·9·10 명령 (bastion 단계 공통)
```

## 배포 순서

### 0) [본 PC·PowerShell] 도구 준비 + 콘솔 자격증명 로그인 + 사전 변수

> **모든 단계를 지급받은 root 로 수행한다.** 채점도 root 콘솔 세션으로 진행되므로(채점지에 IAM 사용자를
> 만들라는 지시가 없다) 클러스터 생성자·KMS·S3 신원이 채점 셸과 어긋나지 않는다.
> 액세스 키는 만들지 않는다 — `aws login` 이 콘솔 자격증명으로 임시 크레덴셜을 받는다.

```powershell
aws --version                          # 2.32.0 이상 (aws login 요건)

# 브라우저에서 root 로 콘솔에 로그인해 둔 상태에서 실행
aws login --profile wsc2026            # region = ap-northeast-2
aws configure list --profile wsc2026   # TYPE 열이 login (~/.aws/credentials 가 남아 있으면 그쪽이 이긴다)

# local .env.ps1 — 셸 재시작에도 재사용 (작업 규칙 6, .gitignore 등록됨)
@'
$env:AWS_PROFILE = "wsc2026"
$env:AWS_DEFAULT_REGION = "ap-northeast-2"
'@ | Set-Content .env.ps1
. .\.env.ps1   # 새 터미널로 이어서 할 땐 set-03/task-1 에서 이 줄만 다시 실행
aws sts get-caller-identity --query Arn --output text   # arn:aws:iam::<계정ID>:root 확인
# 세션은 최대 12시간(15분마다 자동 갱신). ExpiredToken 이 뜨면 aws login --profile wsc2026 재실행

# terraform·eksctl 이 login 프로파일을 못 읽으면(SDK 미지원) 아래를 ~/.aws/config 에 덧붙이고
# $env:AWS_PROFILE 을 wsc2026-proc 으로 바꾼다. CLI 가 자격증명을 대신 넘겨준다.
#   [profile wsc2026-proc]
#   credential_process = aws configure export-credentials --profile wsc2026 --format process
#   region = ap-northeast-2

# 배포파일을 이 과제의 app/ 로 복사 (원본은 shared, 수정 금지)
Copy-Item ..\..\shared\provided\task-1\* .\app\

# 대회 당일 바뀌는 값 — player_number = 선수 비번호(S3 버킷 이름), bucket_suffix = 소문자 영문 4자리
@'
player_number = "00"
bucket_suffix = "abcd"
'@ | Set-Content terraform\terraform.tfvars
```

### 1) [본 PC·PowerShell] Terraform 1차 (네트워크 + AWS 리소스, CDN 제외)

```powershell
cd terraform
terraform init
terraform apply
terraform output -json | Set-Content ..\outputs.json   # PS7 기본 UTF-8 no BOM → bastion jq OK

# SSM 에는 파일 전송이 없어 S3 를 릴레이로 쓴다 (_transfer/ 는 step 9-3 에서 삭제).
# bastion 홈은 유지되므로 이 전송은 1회면 된다.
$o = Get-Content ..\outputs.json | ConvertFrom-Json
$BUCKET = $o.s3_bucket_name.value
aws s3 cp ..\outputs.json "s3://$BUCKET/_transfer/outputs.json"
tar czf "$env:TEMP\wsc2026-cs.tgz" -C .. k8s
aws s3 cp "$env:TEMP\wsc2026-cs.tgz" "s3://$BUCKET/_transfer/wsc2026-cs.tgz"
aws s3 cp ..\mark.sh "s3://$BUCKET/_transfer/mark.sh"   # step 9-2 용 (VPC CloudShell 은 업로드 UI 없음)
```

### 2) [일반 CloudShell] 컨테이너 이미지 빌드 & ECR push (v1.0.0 단일 태그)

> 콘솔에서 **일반 CloudShell**(VPC environment 아님)을 열고 **Actions → Upload file** 로 `app/` 의
> `Dockerfile` 과 `book` 두 파일을 올린다. CloudShell 은 콘솔 로그인 자격증명을 그대로 물려받으므로
> `aws configure` 가 필요 없다 — root 로 로그인한 콘솔에서 열기만 하면 된다.

```bash
aws configure set default.region ap-northeast-2
aws sts get-caller-identity --query Arn --output text   # arn:aws:iam::<계정ID>:root
mkdir -p ~/book-image && mv ~/Dockerfile ~/book ~/book-image/ && cd ~/book-image

ECR=$(aws ecr describe-repositories --repository-names wsc2026-book-ecr --query 'repositories[0].repositoryUri' --output text)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" .    # 태그 v1.0.0 하나만 (latest 금지 — mark 3-1)
docker push "$ECR:v1.0.0"

# scan 완료 / 취약점 0 확인 (요구사항 6)
aws ecr wait image-scan-complete --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0 || \
  { aws ecr start-image-scan --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0; \
    aws ecr wait image-scan-complete --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0; }
aws ecr describe-image-scan-findings --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0 \
  --query 'imageScanFindings.findingSeverityCounts'   # null/빈 값이어야 함
aws ecr list-images --repository-name wsc2026-book-ecr --query 'imageIds[].imageTag'   # ["v1.0.0"] 만
```

### 3) [본 PC·PowerShell] EKS 클러스터 (eksctl)

```powershell
cd ..\eksctl
# terraform outputs → 환경변수 (cluster.yaml 의 ${VAR} 자리)
$o = Get-Content ..\outputs.json | ConvertFrom-Json
$env:VPC_ID             = $o.vpc_id.value
$env:CP_EXTRA_SG_ID     = $o.eks_cp_extra_sg_id.value
$env:NODE_SHARED_SG_ID  = $o.eks_shared_node_sg_id.value
$env:PRIV_SUBNET_A      = $o.private_subnet_ids.value.'wsc2026-skills-app-sub-a'
$env:PRIV_SUBNET_B      = $o.private_subnet_ids.value.'wsc2026-skills-app-sub-b'
$env:EKS_KMS_ARN        = $o.eks_kms_arn.value
$env:BOOK_POD_ROLE_ARN  = $o.pod_identity_role_arns.value.book_pod
$env:LBC_ROLE_ARN       = $o.pod_identity_role_arns.value.lbc
$env:FLUENTBIT_ROLE_ARN = $o.pod_identity_role_arns.value.fluentbit
$env:GRAFANA_ROLE_ARN   = $o.pod_identity_role_arns.value.grafana

# ${VAR} 렌더
$c = Get-Content cluster.yaml -Raw

# 치환 전: cluster.yaml 이 요구하는 env 가 전부 등록됐는지 검사.
# 검사 없이 치환하면 누락된 env 가 빈 문자열로 조용히 들어가고 20분 뒤 create 가 깨진다.
$vars = [regex]::Matches($c, '\$\{(\w+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$missing = $vars | Where-Object { -not (Test-Path "env:$_") }
if ($missing) { throw "env 누락: $($missing -join ', ') — .env.ps1 을 다시 source" }

$vars | ForEach-Object { $c = $c.Replace('${' + $_ + '}', (Get-Item "env:$_").Value) }
$c | Set-Content cluster.rendered.yaml

# 치환 후: 잔여 ${} 가 없어야 함 (출력 없음 = 정상)
Select-String '\$\{' cluster.rendered.yaml

# 셸 재시작 대비 — .env.ps1 통째로 재작성 (덮어쓰기라 중복 누적 없음, 작업 규칙 6)
$keep = @('AWS_PROFILE','AWS_DEFAULT_REGION') + $vars
$keep | ForEach-Object { "`$env:$_ = `"$((Get-Item "env:$_").Value)`"" } | Set-Content ..\.env.ps1

eksctl create cluster -f cluster.rendered.yaml   # 약 20분. 완료 시 자동 private 전환
aws eks describe-cluster --name wsc2026-eks-cluster `
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,endpointPrivateAccess]'   # false, true
# true 로 남았으면:
# aws eks update-cluster-config --name wsc2026-eks-cluster --resources-vpc-config endpointPublicAccess=false
```

### 4) [본 PC → bastion] SSM 접속 + 셋업 (최초 1회)

kubectl·helm·jq·AWS CLI(2.32.0+) 는 bastion_user_data.sh 가 부팅 때 설치해 둔다.
홈이 유지되므로 이 블록은 1회만 실행한다.

```powershell
# [본 PC] cwd = terraform
aws ssm start-session --target (terraform output -raw bastion_instance_id)
```

```bash
# ---- bastion 최초 1회 ----
aws --version        # 2.32.0 이상. 미달이면 user_data 갱신이 실패한 것 — 아래로 직접 갱신한다
# curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
# unzip -q -o /tmp/awscli.zip -d /tmp && sudo /tmp/aws/install --update && hash -r
aws login --remote   # 출력 URL 을 본 PC 브라우저에서 열어 root 로 로그인 →
                     # 표시된 authorization code 를 이 터미널에 붙여넣는다. region = ap-northeast-2
                     # 클러스터 생성 신원과 같아야 kubectl 이 된다 (cluster.yaml bootstrapClusterCreatorAdminPermissions)
aws configure list                                      # TYPE 열이 login
aws sts get-caller-identity --query Arn --output text    # 본 PC·채점 셸과 같은 신원(root)

BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
mkdir -p ~/wsc2026 && cd ~/wsc2026
aws s3 cp "s3://$BUCKET/_transfer/wsc2026-cs.tgz" . && tar xzf wsc2026-cs.tgz
aws s3 cp "s3://$BUCKET/_transfer/outputs.json" .

cat > ~/.env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export VPC_ID=$(jq -r '.vpc_id.value' outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' outputs.json)
EOF
grep -qxF 'source ~/.env' ~/.bashrc || echo 'source ~/.env' >> ~/.bashrc   # 재접속 시 자동 (작업 규칙 6)
source ~/.env

aws eks update-kubeconfig --name wsc2026-eks-cluster --region ap-northeast-2
# kubelet clusterDomain 확인 (wsc2026.skills.local)
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq -r .kubeletconfig.clusterDomain
```

> 중간에 manifest 를 고칠 땐 bastion 의 `~/wsc2026/k8s` 를 직접 편집하고 step 5 를 다시 돌린다.
> bastion 은 작업 사본이고 저장소가 원본이다 — 확정된 내용은 step 9 백업으로 회수해 저장소에 반영한다.

### 5) [bastion] k8s manifest 렌더 + CoreDNS 내부 도메인 패치

모든 manifest 를 `rendered/` 로 렌더한 뒤 step 6 에서 폴더 하나를 apply 한다.
`00-namespaces` 와 CoreDNS 만 여기서 먼저 적용한다 — helm(step 6)이 `observability` 네임스페이스를
쓰고, PrometheusRule CRD 는 그 helm 이 설치하기 때문이다.

```bash
cd ~/wsc2026/k8s
rm -rf rendered

# 치환 전: manifest 가 요구하는 env 가 전부 등록됐는지 검사
VARS=$(grep -rhoE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' --include='*.yaml' . | tr -d '${}' | sort -u)
MISSING=$(for v in $VARS; do [ -n "${!v}" ] || echo "$v"; done)
[ -n "$MISSING" ] && echo "env 누락: $MISSING — source ~/.env"

# 렌더: k8s/ 구조 그대로 rendered/ 에 미러. helm values 는 kubectl 대상이 아니라 제외
SED=(-e '')   # VARS 가 비어도 sed 가 첫 파일명을 스크립트로 먹지 않게 하는 시드
for v in $VARS; do SED+=(-e "s|\${$v}|${!v}|g"); done
for f in $(find * -name '*.yaml' ! -name 'kube-prometheus-stack-values.yaml'); do
  mkdir -p "rendered/$(dirname "$f")"
  sed "${SED[@]}" "$f" > "rendered/$f"
done

# dashboard.json 은 manifest 가 아니라 ConfigMap 으로 만들어 rendered/ 에 넣는다 (일괄 apply 대상)
kubectl create configmap wsc2026-grafana-dashboard -n observability \
  --from-file=dashboard.json=monitoring/dashboard.json --dry-run=client -o yaml \
  | kubectl label --local -f - -o yaml grafana_dashboard=1 > rendered/monitoring/99-dashboard-cm.yaml

# 치환 후: 잔여 ${} 가 없어야 함 (출력 없음 = 정상)
grep -rn '\${' rendered && echo '치환 누락!' || echo OK

# helm 이 쓸 네임스페이스 + CoreDNS 패치만 먼저
kubectl apply -f rendered/00-namespaces.yaml -f rendered/01-coredns-wsc2026.yaml
kubectl -n kube-system rollout restart deploy/coredns
kubectl -n kube-system rollout status deploy/coredns
# 검증: wsc2026.skills.local 존으로 해석
kubectl run dns-test --rm -it --restart=Never --image=busybox \
  --overrides='{"spec":{"nodeSelector":{"wsc2026/node":"addon"}}}' \
  -- nslookup kubernetes.default.svc.wsc2026.skills.local
```

### 6) [bastion] Helm 애드온 + k8s 리소스 일괄 apply

```bash
# 6-1) AWS Load Balancer Controller (SA 는 Pod Identity 로 권한 획득)
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.13.4 -n kube-system \
  --set clusterName=wsc2026-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 --set vpcId="$VPC_ID" \
  --set nodeSelector.wsc2026/node=addon

# 6-2) kube-prometheus-stack (release: monitoring — mark 11-1 파드 이름 카운트와 정합)
#      PrometheusRule CRD 를 여기서 설치하므로 6-3 일괄 apply 보다 반드시 먼저 실행한다
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 87.2.1 -n observability -f monitoring/kube-prometheus-stack-values.yaml

# 6-3) 나머지 k8s 리소스 전부 한 번에 (00-namespaces 가 사전순 첫 파일 → ns 부터 적용)
kubectl apply -R -f rendered/

# ALB 프로비저닝 확인 (2차 terraform 의 data.aws_lb 조건)
kubectl get ingress -n wsc2026    # ADDRESS 에 wsc2026-app-alb-...elb.amazonaws.com
aws elbv2 describe-load-balancers --names wsc2026-app-alb --query 'LoadBalancers[0].State.Code'   # active
```

### 7) [본 PC·PowerShell] Terraform 2차 (CloudFront / WAF / 버킷 정책 / Lambda permission)

```powershell
cd ..\terraform
terraform apply -var="enable_cdn=true"     # player_number/bucket_suffix 는 tfvars (step 0)
terraform output -raw cloudfront_domain    # 이후 $CF 로 사용
```

### 8) [bastion] E2E 검증 + 실측 확인

```bash
CF=<cloudfront_domain>   # step 7 출력
# 루트(정적 페이지) 200
curl -s -o /dev/null -w '%{http_code}\n' "https://$CF/"
# POST /booking → booking_id
BID_RESP=$(curl -s -X POST "https://$CF/booking" -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2025"}')
echo "$BID_RESP"
BOOKING_ID=$(echo "$BID_RESP" | jq -r .booking_id)
# GET /v1/book — 필드 순서(client_id,username,email,concert_name,created_at)와 KST 포맷 확인 (mark 9-3)
curl -s "https://$CF/v1/book?booking_id=$BOOKING_ID"
# created_at 저장 원본 포맷 실측
aws dynamodb scan --table-name wsc2026-book-table --max-items 1 --query 'Items[0].created_at'

# 로그 기반 메트릭 실명 확인 (prometheus-rules/dashboard 의 메트릭 이름과 대조)
FB_POD=$(kubectl get pods -n observability -l app=fluent-bit -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n observability "$FB_POD" -- curl -s localhost:2021/metrics | grep -o '^log_metric[a-z_0-9]*' | sort -u

# Grafana LB / datasource / 대시보드 (mark 11-2)
GRAFANA_LB=$(kubectl get svc -n observability monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -u admin:'Skills$#$@!' "http://$GRAFANA_LB/api/datasources" | jq -r '.[].name'   # alertmanager cloudwatch prometheus
curl -s -u admin:'Skills$#$@!' "http://$GRAFANA_LB/api/search?query=wsc2026" | jq -r '.[].title'

# CloudWatch 앱 로그 (Reference02 형식)
aws logs tail /wsc2026/eks/book-app --since 10m | head -5
```

### 9) [bastion → 본 PC] 작업물 백업

bastion 은 step 9-3 에서 지운다. 그 전에 `rendered/`(실제로 apply 된 결과물)와 bastion 에서 직접 고친
manifest 를 본 PC 로 회수한다. S3 에 두면 안 된다 — `_transfer/` 는 채점 전에 비워야 한다(mark 6-1).

```bash
# [bastion] 릴레이를 역방향으로 한 번 더 쓴다
tar czf ~/_backup.tgz -C ~ .env -C ~/wsc2026 k8s
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
aws s3 cp ~/_backup.tgz "s3://$BUCKET/_transfer/"
```

```powershell
# [본 PC] cwd = terraform
$BUCKET = terraform output -raw s3_bucket_name
aws s3 cp "s3://$BUCKET/_transfer/_backup.tgz" ..\_backup.tgz
New-Item -ItemType Directory -Force ..\_backup | Out-Null
tar xzf ..\_backup.tgz -C ..\_backup
# ..\_backup\k8s 를 저장소 k8s\ 와 대조해 bastion 에서 고친 내용을 반영한다
```

### 9-2) [VPC CloudShell] 채점 경로 확인

채점은 CloudShell + `mark-sg` 에서 진행된다(mark.md 유의 11). 제출 전 같은 경로에서 1회 확인한다.
**여기서 실패하면 bastion 이 살아 있어야 고칠 수 있다 — 9-3 은 반드시 이 단계 뒤에.**

> 콘솔 CloudShell → **Actions → Create VPC environment** → VPC `wsc2026-skills-vpc`,
> Subnet `wsc2026-skills-app-sub-a`, SG `mark-sg`.
> 여기가 채점과 같은 경로다 — 신원까지 같아야 의미가 있으므로 **root 로 로그인한 콘솔에서 연다**.
> `check_kms` 5건과 7-1 Lambda 환경변수는 신원이 어긋나면 그대로 FAIL 로 나온다.

```bash
aws configure set default.region ap-northeast-2
aws sts get-caller-identity --query Arn --output text   # arn:aws:iam::<계정ID>:root
# root 가 아니면 여기서 교정한다 (콘솔 로그아웃 없이)
# aws login --remote --profile wsc2026 && export AWS_PROFILE=wsc2026

sudo curl -sLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo chmod +x /usr/local/bin/kubectl
aws eks update-kubeconfig --name wsc2026-eks-cluster --region ap-northeast-2

# VPC environment 는 업로드 UI 가 없다 — mark.sh 도 step 1 릴레이로 받는다
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
aws s3 cp "s3://$BUCKET/_transfer/mark.sh" . && chmod +x mark.sh
./mark.sh       # 저장소 재현본. 심사는 자기들 원본으로 채점한다
```

### 9-3) [본 PC·PowerShell] 채점 전 정리 (_transfer + bastion 제거)

```powershell
# S3 릴레이 제거 (static/ 만 남긴다 — mark 6-1)
aws s3 rm "s3://$BUCKET/_transfer/" --recursive

# bastion 제거. enable_cdn=true 를 같이 넘겨야 step 7 의 CloudFront/WAF 가 유지된다
terraform apply -var="enable_cdn=true" -var="enable_bastion=false"
```

### 10) 전체 destroy (채점 종료 후)

생성 역순으로 지운다. ALB 와 클러스터가 남아 있으면 Terraform 이 서브넷·SG 를 못 지운다.

```bash
# 10-1) [VPC CloudShell] ingress 삭제 → LBC 가 ALB 를 회수한다
#       bastion 은 step 9-3 에서 지웠으므로 9-2 의 CloudShell 에서 실행한다
kubectl delete ingress -n wsc2026 --all
```

```powershell
# 10-2) [본 PC] 클러스터 (step 9-3 이후 cwd = terraform)
cd ..\eksctl
eksctl delete cluster -f cluster.rendered.yaml

# 10-3) [본 PC] DynamoDB 삭제 방지 해제
#       dynamodb.tf 는 고치지 않는다 (mark 2-1 검사 대상) — CLI 로만 해제한다
aws dynamodb update-table --table-name wsc2026-book-table --no-deletion-protection-enabled

# 10-4) [본 PC] S3 객체 비우기 (force_destroy 미설정 — 객체가 남으면 destroy 가 실패한다)
$BUCKET = aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text
aws s3 rm "s3://$BUCKET" --recursive

# 10-5) [본 PC] 나머지 전부. enable_cdn 기본값(false)으로 돌려 data.aws_lb 조회를 건너뛴다.
#       CloudFront 는 비활성화→삭제에 시간이 걸린다
cd ..\terraform
terraform destroy
```
