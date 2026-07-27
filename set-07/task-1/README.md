# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 — Unicorn Tickets Solution Architecture

EKS 기반 콘서트 예약 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 구성한 결과물.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준(단, CloudFront/WAF 및 Platform KMS 프라이머리는 `us-east-1`).
본 PC 단계는 **PowerShell 7** 기준이다 — 본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 쓴다
(CloudShell/bastion 단계는 공통).

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
README.linux.md          # 본 PC 가 Linux 일 때의 step 0·1·3·10 명령 (나머지 단계 공통)
```

> 제공된 배포파일(`book`, `index.html`, `main.jpeg`)은 repo 공용 `shared/provided/task-1/` 에 있다.
> S3 정적 업로드(`s3.tf`)는 이 경로를 직접 읽고, App 이미지 빌드는 `book` 을 S3 릴레이로 CloudShell 에 넘긴다.

## 배포 순서

> **머신 4분할** — ① **본 PC(PowerShell 7)**: `terraform apply` (state 가 여기 있다).
> ② **일반 CloudShell**: 컨테이너 빌드/푸시 — 대회 PC 는 Docker·WSL 을 못 쓴다.
> ③ **작업용 SSM bastion**(임시 EC2): eksctl/helm/kubectl·디버깅 — CloudShell 의 30분 타임아웃·툴 부재를 피한다.
> ④ **`unicorn-mark` CloudShell**: 채점 전용(유의사항 14).
> 본 PC 는 tfstate 대신 `outputs.json`+프로젝트 번들을 **S3 릴레이**로 넘기고, 작업 호스트는 거기서 받는다
> (tfstate·`.terraform/` 은 올리지 않는다). bastion 은 작업 전용이라 **채점 전 삭제**(step 10) — 삭제 전에
> 상태를 본 PC 로 회수하므로 언제든 복구할 수 있다.
> private cluster 라 eksctl 은 VPC 내부(bastion/CloudShell)에서만 가능하다.

### 0) [본 PC·PowerShell] 사전 변수

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-2"
$env:NUM = "<선수등번호>"     # ExternalId / Grafana 계정에 사용
```

> 자격증명은 **채점 때 콘솔에 로그인할 신원과 같은 것**을 쓴다. 대회에서 root 사용을 금지하지 않으면
> 선수는 보통 root 로 운영하므로, 그 경우 본 PC·bastion 모두 root 액세스 키를 쓴다. 이유는 step 4 참고.

### 1) [본 PC·PowerShell] Terraform (네트워크 + AWS 리소스)

```powershell
cd terraform
terraform init
terraform apply -var "player_number=$env:NUM"
terraform output -json | Set-Content ..\outputs.json   # PS7 기본 UTF-8 no BOM → 원격 jq 가 읽는다

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

# 작업 호스트는 파일 업로드 UI 가 없고 레포가 비공개라 git clone 도 불가 → S3 를 릴레이로 쓴다.
# _transfer/ 는 채점 전 step 10 에서 비운다 (web 버킷은 채점 대상 — mark.sh 3-1-A).
aws s3 cp ..\outputs.json "s3://$env:BUCKET/_transfer/outputs.json"
tar czf "$env:TEMP\unicorn-cs.tgz" -C .. eksctl k8s mark.sh
aws s3 cp "$env:TEMP\unicorn-cs.tgz" "s3://$env:BUCKET/_transfer/unicorn-cs.tgz"

# step 2(일반 CloudShell)의 이미지 빌드 재료 — 본 PC 엔 Docker 가 없다
aws s3 cp ..\app\Dockerfile "s3://$env:BUCKET/_transfer/Dockerfile"
aws s3 cp ..\..\..\shared\provided\task-1\book "s3://$env:BUCKET/_transfer/book"
```

> Pod Identity 역할·SG·VPC Endpoint 는 Terraform 이 먼저 만들어야 eksctl 이 참조하므로 1) 을 가장 먼저 끝낸다.

### 2) [일반 CloudShell] 컨테이너 이미지 빌드 & ECR push (v1.0.0 + latest)

> 콘솔에서 **일반 CloudShell**(VPC environment 아님)을 연다 — Docker 와 인터넷 egress 가 둘 다 필요하다.
> 대회 PC 는 Docker·WSL 을 못 쓰므로 빌드는 여기서 한다.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
mkdir -p ~/book-image && cd ~/book-image
aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/Dockerfile" .
aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/book" .     # 제공 바이너리 (수정 금지)

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

### 3) [본 PC·PowerShell] 작업용 SSM bastion 생성 (수동 · 임시)

> private 서브넷 EC2 + **`unicorn-mark-sg` 공유** + SSM 접속(인바운드 0). EKS API(443) 는 cp-extra SG 가
> `unicorn-mark-sg` 에 열어두므로 이 bastion 에서 바로 kubectl 가능.
> 인스턴스 프로파일은 **SSM 전용**만 부여한다(작업 자격증명은 4) 에서 `aws configure`). Name 태그를
> 노드(`unicorn-k8snode-*`)와 다르게 줘 mark.sh 인스턴스 카운트에 안 걸리게 한다. **채점 전 삭제**(step 10).

```powershell
cd terraform    # outputs.json 은 ..\outputs.json
. ..\.env.ps1   # 새 창이면

$o = Get-Content ..\outputs.json | ConvertFrom-Json
$SUBNET  = $o.private_subnet_ids.value.'unicorn-subnet-priv-a'
$MARK_SG = $o.mark_sg_id.value
$AMI = aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 `
  --query Parameter.Value --output text

# IAM: SSM 접속용만 (작업 권한은 4) 의 aws configure 로 주입)
# 인라인 JSON 은 Windows AWS CLI 에서 따옴표가 깨지므로 파일로 넘긴다
@'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
'@ | Set-Content "$env:TEMP\bastion-trust.json"

aws iam create-role --role-name unicorn-bastion-role `
  --assume-role-policy-document "file://$env:TEMP\bastion-trust.json"
aws iam attach-role-policy --role-name unicorn-bastion-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name unicorn-bastion-profile
aws iam add-role-to-instance-profile --instance-profile-name unicorn-bastion-profile --role-name unicorn-bastion-role
Start-Sleep 10   # instance profile 전파 대기

# EC2 (인바운드 없음, IMDSv2 강제)
$BID = aws ec2 run-instances --image-id "$AMI" --instance-type t3.small `
  --iam-instance-profile Name=unicorn-bastion-profile `
  --subnet-id "$SUBNET" --security-group-ids "$MARK_SG" `
  --metadata-options HttpTokens=required,HttpEndpoint=enabled `
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=unicorn-bastion}]' `
  --query 'Instances[0].InstanceId' --output text
echo "bastion=$BID"   # step 10 삭제에 사용

# 등록까지 1–2분 후 접속 (본 PC 에 session-manager-plugin 필요, 또는 콘솔 EC2 → Connect → Session Manager)
aws ssm start-session --target "$BID"
```

### 4) [bastion] 도구 설치 · 자격증명 · 파일 수신 · 환경 변수

> **`aws configure` 에는 채점 때 콘솔에 로그인할 그 자격증명을 넣는다** — root 로 운영하면 root 액세스 키를,
> 별도 IAM 사용자를 만들었으면 그 키를. 그래야 **클러스터 생성자 = 채점 CloudShell 신원** 이 되어
> (`bootstrapClusterCreatorAdminPermissions`) bastion 삭제 후에도 채점 셸 kubectl 권한이 유지된다.
> 인스턴스 프로파일(SSM) 보다 `~/.aws` 자격증명이 우선한다. 신원이 어긋나면 step 9 게이트에서 걸린다.

```bash
sudo dnf install -y jq tar gzip
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp && sudo install -m755 /tmp/eksctl /usr/local/bin/eksctl
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install -m755 kubectl /usr/local/bin/kubectl
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

aws configure   # 위 인용문 참고, default region = ap-northeast-2

# 파일 (S3 릴레이) + NUM
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export NUM=<선수등번호>
mkdir -p ~/unicorn && cd ~/unicorn
aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/unicorn-cs.tgz" . && tar xzf unicorn-cs.tgz
aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/outputs.json" .

# 환경 변수 (tfstate 없이 jq 로 outputs.json 을 읽는다). bastion 은 영속 디스크라 ~/.env 가 세션 간 유지된다.
# 변수명은 k8s/eksctl manifest 의 ${VAR} 자리와 정확히 일치한다.
cat > ~/.env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=$NUM
export ACCOUNT_ID=$(jq -r '.account_id.value' outputs.json)
export VPC_ID=$(jq -r '.vpc_id.value' outputs.json)
export PLATFORM_KMS_ARN=$(jq -r '.platform_kms_arn.value' outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["unicorn-subnet-priv-a"]' outputs.json)
export PRIV_SUBNET_B=$(jq -r '.private_subnet_ids.value["unicorn-subnet-priv-b"]' outputs.json)
export PRIV_SUBNET_C=$(jq -r '.private_subnet_ids.value["unicorn-subnet-priv-c"]' outputs.json)
export CP_EXTRA_SG_ID=$(jq -r '.eks_cp_extra_sg_id.value' outputs.json)
export NODE_SHARED_SG_ID=$(jq -r '.eks_shared_node_sg_id.value' outputs.json)
export BOOK_APP_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.book_app' outputs.json)
export LBC_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.lbc' outputs.json)
export FLUENTBIT_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.fluentbit' outputs.json)
export CWEXPORTER_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.cwexporter' outputs.json)
export EBS_CSI_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.ebs_csi' outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' outputs.json)
export APP_TG=$(jq -r '.app_target_group_arn.value' outputs.json)
export GRAFANA_TG=$(jq -r '.grafana_target_group_arn.value' outputs.json)
export CF=$(jq -r '.cloudfront_domain.value' outputs.json)
export GRAFANA_USER=skills$NUM
export GRAFANA_PW='HelloKrSkills!'$NUM'@'
EOF
grep -qxF 'source ~/.env' ~/.bashrc || echo 'source ~/.env' >> ~/.bashrc
source ~/.env
```

### 5) [bastion] EKS 클러스터 (eksctl)

manifest 의 `${VAR}` 를 렌더한다. **치환 전** 필요한 env 가 다 있는지 검사하고, **치환 후** 잔여 `${}` 가
없는지 검사한다 — 빈 값이 박힌 채로 클러스터가 만들어지면 채점 때야 드러난다.

```bash
cd ~/unicorn/eksctl
rm -f cluster.rendered.yaml   # 이전 실행 잔재로 검사를 통과하는 일이 없게

# 치환 전: cluster.yaml 이 요구하는 env 가 전부 선언됐는지 검사
missing=$(for v in $(grep -oh '[$]{[A-Za-z_][A-Za-z_0-9]*}' cluster.yaml | tr -d '${}' | sort -u); do
  [ -z "${!v}" ] && echo "$v"; done)

if [ -n "$missing" ]; then
  echo "env 누락: $missing — step 4 의 ~/.env 를 다시 source"
else
  # envsubst(gettext) 미설치 대비 python3 — 미선언 변수를 빈 값으로 지우지 않고 ${VAR} 그대로 남기므로
  # 아래 사후 검사에 걸린다.
  python3 -c 'import os,sys;sys.stdout.write(os.path.expandvars(sys.stdin.read()))' \
    < cluster.yaml > cluster.rendered.yaml
  # 치환 후: 잔여 ${} 가 없어야 함
  grep -n '\${' cluster.rendered.yaml && echo '치환 누락!' || echo OK
fi

# 위에서 OK 가 나왔을 때만 진행 (렌더 실패 시 파일이 없어 eksctl 이 바로 멈춘다)
eksctl create cluster -f cluster.rendered.yaml     # 약 20분
aws eks update-kubeconfig --name unicorn-eks-cluster --region ap-northeast-2
```

> bastion 은 유휴 타임아웃이 없어 단일 생성으로 충분하다. (그래도 끊기면 eksctl 은 CloudFormation 기반이라 같은 명령 재실행으로 수렴.)
> addon 버전은 `eksctl utils describe-addon-versions --kubernetes-version 1.35 --name <addon>` 로 확인 후 cluster.yaml 에 고정한다.

### 6) [bastion] Helm 애드온 (Addon NodeGroup)

```bash
cd ~/unicorn/k8s

# 6-1) AWS Load Balancer Controller (SA 는 Pod Identity 로 권한 획득)
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.13.4 -n kube-system \
  --set clusterName=unicorn-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 --set vpcId="$VPC_ID" \
  --set nodeSelector.unicorn=addon

# 6-2) kube-prometheus-stack (release: unicorn-monitoring). 차트 버전 고정(작업규칙 2).
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update

# Grafana 계정 렌더 — step 5 와 같은 검사 패턴 (helm values 라 kubectl 대상이 아니어서 따로 렌더)
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

# 6-3) CloudWatch Exporter (ALB TargetResponseTime → Prometheus). placeholder 없음 — 원본 그대로 쓴다.
helm upgrade --install cloudwatch-exporter prometheus-community/prometheus-cloudwatch-exporter \
  --version 0.28.1 -n monitoring -f monitoring/cloudwatch-exporter-values.yaml
```

### 7) [bastion] Kubernetes 리소스 (렌더 → 일괄 apply)

모든 manifest 를 `rendered/` 에 렌더한 뒤 폴더 하나를 apply 한다. 파일별 `sed | kubectl apply` 는 치환 누락을
조용히 통과시키므로, 렌더 결과를 파일로 남겨 검사한 다음 적용한다.

```bash
cd ~/unicorn/k8s
rm -rf rendered

# helm values(step 6)와 그 렌더 결과(kps-values.rendered.yaml)는 kubectl 대상이 아니므로 제외
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
> grafana TGB 는 step 6 helm 이 Grafana Service 를 이미 만든 뒤라 바로 바인딩된다.

### 8) [bastion] 데이터/트래픽 시드 (대시보드 데이터 확보)

```bash
source ~/.env
curl -s -X POST "https://$CF/v1/book" -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2025"}'   # booking_id 반환
for i in $(seq 1 20); do curl -s -o /dev/null "https://$CF/health"; done                              # ALB 메트릭 생성
```

### 9) [채점용 CloudShell] `unicorn-mark` 생성 + 채점 준비

> 채점은 반드시 `unicorn-mark` CloudShell 에서 한다(유의사항 14). 작업용 bastion 과 별개로 **반드시 생성**한다. kubectl·jq 는 CloudShell 기본 제공.

1. 콘솔 CloudShell → **Actions → Create VPC environment** → Name `unicorn-mark`, VPC `unicorn-vpc`, Subnet `unicorn-subnet-priv-a`, SG `unicorn-mark-sg`.
2. 채점 준비:
   ```bash
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/unicorn-cs.tgz" /tmp/ && tar xzf /tmp/unicorn-cs.tgz -C /tmp mark.sh && cp /tmp/mark.sh ~/   # /home/cloudshell-user (유의사항 13)
   aws eks update-kubeconfig --name unicorn-eks-cluster --region ap-northeast-2
   bash ~/mark.sh
   ```
3. **권한 게이트 — 여기가 통과해야 step 10 으로 넘어간다:**
   ```bash
   aws sts get-caller-identity --query Arn --output text   # step 4 의 aws configure 신원과 같아야 함
   kubectl auth can-i '*' '*'                              # yes
   kubectl get nodes                                       # 노드가 보여야 함
   ```
   > 실패하면 **bastion 을 지우지 말고** 여기서 잡는다. IAM 사용자/역할로 운영 중이면 access entry 를 추가한다:
   > `aws eks create-access-entry --cluster-name unicorn-eks-cluster --principal-arn <ARN>` →
   > `aws eks associate-access-policy --cluster-name unicorn-eks-cluster --principal-arn <ARN> --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster`
   > 계정 root 로 운영 중이라면 이 경로는 보장되지 않는다(root ARN 은 access entry 대상으로 문서화돼 있지 않다).
   > 그때는 step 4 의 `aws configure` 신원을 채점 셸과 맞춰 클러스터를 다시 만드는 것이 확실하다.

### 10) [본 PC·PowerShell] 채점 전 정리 (배포 검증 후)

> 배포 정상 동작과 step 9 권한 게이트를 확인한 뒤, **채점 직전** 작업 전용 리소스만 제거한다.
> 본 인프라·`unicorn-mark` CloudShell 은 남긴다. 삭제 전에 bastion 상태를 본 PC 로 회수하므로 언제든 복구할 수 있다.
> mark.sh 는 bastion 을 검사하지 않지만(Name 태그 분리), 보안 pillar·정리 차원에서 인스턴스+프로파일+role 까지 삭제한다.

**10-1) [bastion] 상태 백업 → S3**

```bash
cd ~ && tar czf ~/unicorn-bastion-state.tgz -C ~ .env unicorn
aws s3 cp ~/unicorn-bastion-state.tgz "s3://unicorn-web-$ACCOUNT_ID/_transfer/"
```

**10-2) [본 PC·PowerShell] 백업 회수 → bastion 삭제 → S3 릴레이 제거**

순서가 중요하다. 회수(10-2 앞부분)를 S3 정리보다 먼저 해야 복구 수단이 남는다.

```powershell
. .\.env.ps1   # 새 창이면 (task-1 에서)

# 백업 회수 — 레포 밖에 둔다
aws s3 cp "s3://$env:BUCKET/_transfer/unicorn-bastion-state.tgz" "$env:TEMP\"

# bastion 삭제
$BID = aws ec2 describe-instances --filters Name=tag:Name,Values=unicorn-bastion Name=instance-state-name,Values=running `
  --query "Reservations[].Instances[].InstanceId" --output text     # 3) 의 $BID 를 모를 때
aws ec2 terminate-instances --instance-ids "$BID"
aws ec2 wait instance-terminated --instance-ids "$BID"
aws iam remove-role-from-instance-profile --instance-profile-name unicorn-bastion-profile --role-name unicorn-bastion-role
aws iam delete-instance-profile --instance-profile-name unicorn-bastion-profile
aws iam detach-role-policy --role-name unicorn-bastion-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name unicorn-bastion-role

# S3 릴레이 제거 (web 버킷은 채점 대상 — mark.sh 3-1-A)
aws s3 rm "s3://$env:BUCKET/_transfer/" --recursive
aws s3api list-objects-v2 --bucket "$env:BUCKET" --prefix _transfer/ --query 'Contents[].Key'  # null 확인
```

> **bastion 복구** — step 3 재실행(EC2+프로파일 재생성) → step 4 의 도구 설치 + `aws configure` 재실행 →
> 본 PC 에서 `$env:TEMP\unicorn-bastion-state.tgz` 를 `_transfer/` 로 재업로드 → bastion 에서 받아
> `tar xzf ~/unicorn-bastion-state.tgz -C ~` → `source ~/.env` + `aws eks update-kubeconfig`.
> 채점이 아직이면 복구 후 `_transfer/` 를 다시 비운다.

> (유의사항 9) 실행 중 부하/테스트 없어야 함 — 8) seed 는 one-shot. DynamoDB seed item 은 채점이 자체 `booking_id` 로 조회하므로 무방.

> **Fallback — bastion 없이 가려면**: 3)·10) 의 bastion 을 건너뛰고, 4)~8) 을 `unicorn-mark` CloudShell 에서 그대로 실행한다(생성자=채점 신원이라 권한 게이트도 자동 통과). 단 CloudShell 제약: ① 30분 유휴 시 환경 삭제 → eksctl 은 `--without-nodegroup` 후 `create nodegroup` 으로 쪼개거나, 끊겨도 같은 명령 재실행으로 수렴. ② 업로드 UI 없음 → 끊기면 S3 릴레이에서 다시 받고 4) 재실행. ③ `eksctl/helm/kubectl` 설치 필요(4) 의 설치 블록 동일), `aws configure` 는 CloudShell 자격증명이 이미 있으면 생략.


## 리소스 정리 유의사항

- DynamoDB 테이블의 리소스 삭제 보호 해제
- S3 비우기 (S3 버전 관리 관련 리소스 존재)

해당 작업을 진행하지 않고 `terraform destroy` 실행 시 리소스가 완전히 삭제되지 않습니다.


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

- 채점은 `unicorn-mark` CloudShell 에서 `bash mark.sh` 로 일괄 실행.
- 핵심 확인: `aws kms get-key-rotation-status`(app/data/platform = True 90), `aws ecr describe-repositories`(IMMUTABLE_WITH_EXCLUSION),
  `kubectl get nodes -l unicorn=app`(2 AZ 이상), `aws eks list-pod-identity-associations`(unicorn-book-app-sa),
  CloudWatch `/unicorn/eks/book-app` 로그 키 = `client_ip,method,path,status_code,timestamp`,
  WAF rate-limit 차단 시 `403 Request blocked by Unicorn WAF`, Grafana `unicorn-grafana-dashboard` 5패널 No Data 없음.

## 주의 / 검증 필요 포인트

- **작업용 bastion 은 임시**: `unicorn-mark-sg` 공유로 private API 에 접근하고, 자격증명은 `aws configure` 로 주입해
  생성자=채점 신원을 맞춘다. 인스턴스 프로파일은 SSM 전용. **채점 전 step 10 으로 인스턴스+프로파일+role 까지 삭제** —
  mark.sh 가 검사하지 않아도 남기지 않는다. 삭제 전 상태를 본 PC 로 회수하므로 복구는 언제든 가능하다.
- **자격증명 신원**: 대회가 root 사용을 금지하지 않으면 선수는 root 로 운영한다. 이 경우 `aws configure` 에도
  root 액세스 키를 넣어 생성자=채점 신원을 맞춘다. 계정 root ARN 은 EKS access entry 대상으로 문서화돼 있지 않아
  **사후 보정이 안 될 수 있으므로**, step 9 권한 게이트를 bastion 삭제 전에 반드시 통과시킨다.
- **Platform KMS = MRK**: 프라이머리(us-east-1)·레플리카(ap-northeast-2) 동일 키 자료. WAF 로그(us-east-1)=프라이머리,
  EKS/EBS/Log(서울)=레플리카. `alias/unicorn-kms-platform` 은 양 리전에 존재. 회전(90일)은 프라이머리가 관리.
- **이미지 풀**: private 서브넷에 NAT 가 있어 공개 레지스트리(LBC/Prometheus/Grafana/Fluent Bit)는 직접 pull.
  App 이미지(ECR)·로그(CloudWatch)는 VPC Endpoint(private DNS)로 인터넷 미경유.
- **Grafana 패널5(HTTP Request Duration)**: ALB TargetResponseTime 기반이라 트래픽이 있어야 데이터 표시 → 8) 시드 수행.
- **EKS Control Plane 로그 그룹**: eksctl 생성 전 Terraform 이 `/aws/eks/<cluster>/cluster` 를 Platform CMK 로 선생성.
