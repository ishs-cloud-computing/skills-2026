# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 — Unicorn Tickets Solution Architecture

EKS 기반 콘서트 예약 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 구성한 결과물.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준(단, CloudFront/WAF 및 Platform KMS 프라이머리는 `us-east-1`).
`terraform apply` 는 본 PC 에서 수행하고, **EKS 구성(eksctl/helm/kubectl)과 채점은 Private Subnet 의 CloudShell VPC 환경 `unicorn-mark`** 에서 한다(EKS API 가 private → VPC 내부에서만 접근).

## 디렉토리 구조

```
terraform/   # AWS 인프라 (VPC/Endpoint/FlowLog, KMS, S3, ECR, DynamoDB, Lambda, ALB, CloudFront, WAF, IAM)
  ├─ versions.tf variables.tf data.tf
  ├─ vpc.tf flowlog.tf endpoints.tf kms.tf
  ├─ s3.tf ecr.tf dynamodb.tf lambda.tf lambda/index.py
  ├─ alb.tf cloudfront.tf waf.tf cloudwatch.tf
  ├─ iam.tf iam/lbc-policy.json security.tf outputs.tf
  └─ assets/static/      # 제공된 index.html, main.jpeg
eksctl/cluster.yaml      # EKS 1.35, private, authMode=API, Pod Identity, 2 NodeGroup(app/addon)
k8s/
  ├─ 00-namespaces.yaml 01-storageclass.yaml
  ├─ app/         # SA, ConfigMap, Deployment(book), Service, PDB, TargetGroupBinding
  ├─ logging/     # Fluent Bit DaemonSet (logfmt → 5키 JSON 재구성)
  └─ monitoring/  # kube-prometheus-stack values, cloudwatch-exporter, grafana TGB, dashboard.json
app/Dockerfile book      # Book App 컨테이너 (alpine + book)
```

## 배포 순서

> **머신 구분** — bastion 이 없는 세트다. `terraform apply` 와 컨테이너 빌드는 **본 PC** 에서, EKS 구성(eksctl/helm/kubectl)·채점은
> **`unicorn-mark` CloudShell** 에서 한다(EKS API 가 private → VPC 내부에서만 접근 가능). 본 PC 는 tfstate 대신 `outputs.json` 만
> CloudShell 로 넘기고, CloudShell 은 `jq` 로 값을 읽는다(tfstate·`.terraform/` 은 절대 올리지 않는다).

### 0) [본 PC] 사전 변수

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=<선수등번호>     # ExternalId / Grafana 계정에 사용
```

### 1) [본 PC] Terraform (네트워크 + AWS 리소스)

```bash
cd terraform
terraform init
terraform apply -var="player_number=$NUM"
terraform output -json > ../outputs.json   # CloudShell 로 넘길 값 (tfstate 는 넘기지 않는다)

# VPC CloudShell 은 파일 업로드 기능이 없으므로 S3 를 릴레이로 쓴다. web 버킷(unicorn-web-<ACCOUNT_ID>)에 임시 업로드.
BUCKET=$(jq -r '.s3_bucket_name.value' ../outputs.json)
aws s3 cp ../outputs.json "s3://$BUCKET/_transfer/outputs.json"
```

> Pod Identity 역할·SG·VPC Endpoint 는 Terraform 이 먼저 만들어야 eksctl 이 참조하므로 1) 을 가장 먼저 끝낸다.

### 2) [본 PC] 컨테이너 이미지 빌드 & ECR push (v1.0.0 + latest)

> CloudShell 에는 Docker 데몬이 없으므로 빌드/푸시는 본 PC 에서 한다.

```bash
cd ../app
ECR=$(jq -r '.ecr_repository_url.value' ../outputs.json)
cp ../provided/book ./book   # 제공 바이너리 (수정 금지)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker buildx build --platform linux/amd64 --provenance=false -t "$ECR:v1.0.0" -t "$ECR:latest" --push .

# scan 완료/취약점 0 확인 (요구사항 7)
aws ecr wait image-scan-complete --repository-name unicorn-concert-app --image-id imageTag=v1.0.0 || \
  { aws ecr start-image-scan --repository-name unicorn-concert-app --image-id imageTag=v1.0.0; \
    aws ecr wait image-scan-complete --repository-name unicorn-concert-app --image-id imageTag=v1.0.0; }
aws ecr describe-image-scan-findings --repository-name unicorn-concert-app --image-id imageTag=v1.0.0 \
  --query 'imageScanFindings.findingSeverityCounts'   # null/빈 값이어야 함
```

### 3) [본 PC → CloudShell] 작업·채점용 CloudShell VPC Environment `unicorn-mark` 생성 (수동)

CloudShell VPC 환경은 IaC 로 생성 불가하므로 콘솔에서 직접 만든다. **이후 eksctl/helm/kubectl 작업은 전부 이 쉘에서** 한다.

1. 콘솔 CloudShell → **Actions → Create VPC environment** → Name `unicorn-mark`.
   - VPC = `unicorn-vpc`
   - Subnet = `unicorn-subnet-priv-a` (priv b/c 도 가능)
   - Security Group = `unicorn-mark-sg` (`jq -r '.mark_sg_id.value' outputs.json`)
2. 작업 파일을 쉘로 가져온다. **VPC CloudShell 은 Upload/Download file 기능이 없으므로** S3·git 으로 받는다(private 서브넷 + NAT/엔드포인트로 outbound 가능).
   ```bash
   # 프로젝트(eksctl/·k8s/·mark.sh) 먼저 받고 작업 디렉토리로 이동
   git clone <repo> && cd <repo>/set-07/task-1
   # outputs.json 은 1) 에서 올린 S3 릴레이에서 작업 디렉토리로 받는다 (버킷명은 account id 로 결정 → 요구사항 5)
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   aws s3 cp "s3://unicorn-web-$ACCOUNT_ID/_transfer/outputs.json" .
   ```
   - 채점 스크립트 `mark.sh` 는 `/home/cloudshell-user` 에 둔다(채점 유의사항 13).
   - 전송 끝나면 릴레이 오브젝트 정리: `aws s3 rm "s3://unicorn-web-$ACCOUNT_ID/_transfer/outputs.json"`.
3. eksctl/helm 설치(미설치 시). kubectl·jq·envsubst 는 CloudShell 기본 제공.
   ```bash
   curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin/
   curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

### 4) [CloudShell] 환경 변수 (`outputs.json` 기반)

본 PC 가 아니라 **CloudShell 에서** 실행한다. tfstate 가 없으므로 `terraform output` 대신 `jq` 로 `outputs.json` 을 읽는다.
연결이 끊겨도 재접속 즉시 쓰도록 `~/.unicorn-env` 로 영구화한다(작업 규칙 6). `NUM` 은 이 쉘에서 다시 export 한다.

```bash
export NUM=<선수등번호>
cat > ~/.unicorn-env <<EOF
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
grep -qxF 'source ~/.unicorn-env' ~/.bashrc || echo 'source ~/.unicorn-env' >> ~/.bashrc
source ~/.unicorn-env
```

> CloudShell VPC environment 는 홈 디렉토리가 영구 보존되지 않고 파일 업로드도 막혀 있다. 세션이 끊기면 3) 처럼 S3·git 으로 `outputs.json`·프로젝트를 다시 받고 4) 를 재실행한다.

### 5) [CloudShell] EKS 클러스터 (eksctl)

```bash
cd eksctl
envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml
aws eks update-kubeconfig --name unicorn-eks-cluster --region ap-northeast-2   # 재접속/다른 신원 시 kubeconfig 갱신
```

> addon 버전은 `eksctl utils describe-addon-versions --kubernetes-version 1.35 --name <addon>` 로 확인 후 cluster.yaml 에 고정한다.
> kubectl 권한: 클러스터 생성자(eksctl 실행 IAM)는 `bootstrapClusterCreatorAdminPermissions` 로 자동 admin.
> 채점자(다른 IAM)가 kubectl 을 써야 하면 access entry 추가:
> `aws eks create-access-entry --cluster-name unicorn-eks-cluster --principal-arn <ARN>` →
> `aws eks associate-access-policy --cluster-name unicorn-eks-cluster --principal-arn <ARN> --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster`

### 6) [CloudShell] Helm 애드온 (Addon NodeGroup)

```bash
# 6-1) AWS Load Balancer Controller (SA 는 Pod Identity 로 권한 획득)
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.13.4 -n kube-system \
  --set clusterName=unicorn-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 --set vpcId="$VPC_ID" \
  --set nodeSelector.unicorn=addon

# 6-2) kube-prometheus-stack (release: unicorn-monitoring). 차트 버전 고정(작업규칙2).
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
sed -e "s|<GRAFANA_ADMIN_USER>|$GRAFANA_USER|g" -e "s|<GRAFANA_ADMIN_PASSWORD>|$GRAFANA_PW|g" \
  ../k8s/monitoring/kube-prometheus-stack-values.yaml > /tmp/kps-values.yaml
helm upgrade --install unicorn-monitoring prometheus-community/kube-prometheus-stack \
  --version 87.2.1 -n monitoring --create-namespace -f /tmp/kps-values.yaml

# 6-3) CloudWatch Exporter (ALB TargetResponseTime → Prometheus)
helm upgrade --install cloudwatch-exporter prometheus-community/prometheus-cloudwatch-exporter \
  --version 0.28.1 -n monitoring -f ../k8s/monitoring/cloudwatch-exporter-values.yaml
```

### 7) [CloudShell] Kubernetes 리소스

```bash
cd ../k8s
kubectl apply -f 00-namespaces.yaml
sed "s|<PLATFORM_KMS_ARN>|$PLATFORM_KMS_ARN|g" 01-storageclass.yaml | kubectl apply -f -

# App (ECR / TargetGroup ARN 치환)
kubectl apply -f app/serviceaccount.yaml -f app/configmap.yaml
sed "s|<ECR_REPOSITORY_URL>|$ECR|g" app/deployment.yaml | kubectl apply -f -
kubectl apply -f app/service.yaml -f app/pdb.yaml
sed "s|<APP_TARGET_GROUP_ARN>|$APP_TG|g" app/targetgroupbinding.yaml | kubectl apply -f -

# Grafana TargetGroupBinding (unicorn-grafana-tg)
sed "s|<GRAFANA_TARGET_GROUP_ARN>|$GRAFANA_TG|g" monitoring/grafana-targetgroupbinding.yaml | kubectl apply -f -

# Grafana 대시보드(sidecar 가 label 로 자동 import)
kubectl create configmap unicorn-grafana-dashboard -n monitoring \
  --from-file=dashboard.json=monitoring/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap unicorn-grafana-dashboard -n monitoring grafana_dashboard=1 --overwrite

# 로깅 (Fluent Bit)
kubectl apply -f logging/fluent-bit.yaml
```

### 8) [CloudShell] 데이터/트래픽 시드 (대시보드 데이터 확보)

```bash
source ~/.unicorn-env
curl -s -X POST "https://$CF/v1/book" -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2025"}'   # booking_id 반환
for i in $(seq 1 20); do curl -s -o /dev/null "https://$CF/health"; done                              # ALB 메트릭 생성
```

### 9) [CloudShell] 채점 전 정리

web 버킷(`unicorn-web-<ACCOUNT_ID>`)은 채점 대상(mark.sh 3-1-A)이므로, 3) 에서 릴레이로 올린 임시 객체가 남아 있으면 제거한다.
(유의사항 9) 실행 중인 부하/테스트가 없어야 한다 — 8) seed 는 one-shot 이라 잔여 부하 없음. DynamoDB seed item 은 채점이 자체 `booking_id` 로 조회하므로 그대로 둬도 무방.

```bash
aws s3 rm "s3://unicorn-web-$ACCOUNT_ID/_transfer/outputs.json"   # 3) 에서 이미 지웠으면 No such key (정상)
aws s3api list-objects-v2 --bucket "unicorn-web-$ACCOUNT_ID" --prefix _transfer/ --query 'Contents[].Key'  # null 확인
```

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

- **Platform KMS = MRK**: 프라이머리(us-east-1)·레플리카(ap-northeast-2) 동일 키 자료. WAF 로그(us-east-1)=프라이머리,
  EKS/EBS/Log(서울)=레플리카. `alias/unicorn-kms-platform` 은 양 리전에 존재. 회전(90일)은 프라이머리가 관리.
- **이미지 풀**: private 서브넷에 NAT 가 있어 공개 레지스트리(LBC/Prometheus/Grafana/Fluent Bit)는 직접 pull.
  App 이미지(ECR)·로그(CloudWatch)는 VPC Endpoint(private DNS)로 인터넷 미경유.
- **Grafana 패널5(HTTP Request Duration)**: ALB TargetResponseTime 기반이라 트래픽이 있어야 데이터 표시 → 8) 시드 수행.
- **EKS Control Plane 로그 그룹**: eksctl 생성 전 Terraform 이 `/aws/eks/<cluster>/cluster` 를 Platform CMK 로 선생성.
