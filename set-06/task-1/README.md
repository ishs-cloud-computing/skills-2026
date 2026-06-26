# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 — Solution Architecture (set-06)

EKS 기반 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 구성한다.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준이다.

## 디렉토리 구조

```
terraform/   # VPC·IGW·Endpoints·KMS·S3·ECR·DynamoDB·Lambda·ALB·CloudFront·WAF·IAM
  ├─ versions.tf variables.tf terraform.tfvars data.tf
  ├─ vpc.tf endpoints.tf kms.tf s3.tf ecr.tf dynamodb.tf
  ├─ lambda.tf lambda/index.py alb.tf
  ├─ cloudfront.tf cloudfront_function.js waf.tf iam.tf outputs.tf
  └─ assets/                  # index.html, main.jpeg (provided 복사본)
eksctl/cluster.yaml           # EKS 1.35 + Bottlerocket NodeGroup 2개
k8s/
  ├─ 00-namespaces.yaml 01-storageclass.yaml
  ├─ app/         # book: configmap, deployment, service, pdb, tgb, securitygrouppolicy
  ├─ monitoring/  # grafana values/ecr-images/dashboard, tgb
  └─ logging/     # aws-for-fluent-bit DaemonSet (AZ별 로그스트림)
app/
  ├─ Dockerfile             # book: FROM scratch + 제공 바이너리 + CA certs (<3MB)
  └─ bootstrap/             # Bottlerocket 노드명 커스텀용 bootstrap container 이미지
provided/                   # 제공자료(수정 금지): book 바이너리, index.html, main.jpeg
```

## 배포 순서

### 1) Terraform (네트워크 + AWS 리소스)

```bash
cd terraform
# terraform.tfvars 의 seat_number 를 대회 비번호로 교체
terraform init
terraform apply
```

작업 변수 캡처(이후 단계가 재사용):

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
export ACCOUNT_ID=$(terraform output -raw account_id)
export VPC_ID=$(terraform output -raw vpc_id)
export SUBNET_A_ID=$(terraform output -json subnet_ids_by_az | jq -r '."ap-northeast-2a"')
export SUBNET_B_ID=$(terraform output -json subnet_ids_by_az | jq -r '."ap-northeast-2b"')
export EKS_KMS_KEY_ARN=$(terraform output -raw eks_kms_key_arn)
export ECR=$(terraform output -raw ecr_repository_url)
export GRAFANA_MIRROR=$(terraform output -raw grafana_mirror_repo_url)
export BOOK_TG=$(terraform output -raw book_target_group_arn)
export GRAFANA_TG=$(terraform output -raw grafana_target_group_arn)
export SHARED_NODE_SG_ID=$(terraform output -raw shared_node_sg_id)
export BOOK_POD_SG_ID=$(terraform output -raw book_pod_sg_id)
export CF_DOMAIN=$(terraform output -raw cloudfront_domain)
export DistributionID=$(terraform output -raw cloudfront_distribution_id)
export BOOK_APP_POLICY_ARN=$(terraform output -json iam_policy_arns | jq -r .book_app)
export FLUENTBIT_POLICY_ARN=$(terraform output -json iam_policy_arns | jq -r .fluentbit)
export GRAFANA_CW_POLICY_ARN=$(terraform output -json iam_policy_arns | jq -r .grafana_cw)
export EBS_CSI_POLICY_ARN=$(terraform output -json iam_policy_arns | jq -r .ebs_csi)
export ECR_PULL_THROUGH_POLICY_ARN=$(terraform output -json iam_policy_arns | jq -r .ecr_pull_through)
```

### 2) 컨테이너 이미지 빌드 & ECR push (인터넷 있는 운영 머신)

```bash
cd ..   # set-06/task-1 (build context)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"

# book 이미지: 제공 바이너리(수정 금지) → scratch. zstd 레이어 압축으로 <3MB.
docker buildx build --platform linux/amd64 --provenance=false -f app/Dockerfile \
  --output type=image,name=$ECR:latest,compression=zstd,compression-level=19,force-compression=true,push=true .
aws ecr describe-images --repository-name book --image-ids imageTag=latest \
  --query 'imageDetails[0].imageSizeInBytes' --output text   # <= 3145728(3MB) 확인

# Bottlerocket 노드명 커스텀용 bootstrap 이미지
BOOTSTRAP=${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/gj2026-bootstrap
docker buildx build --platform linux/amd64 --provenance=false -f app/bootstrap/Dockerfile -t $BOOTSTRAP:latest --push .

# Grafana 이미지(Docker Hub 전용) → 사설 ECR 미러
docker pull grafana/grafana:11.6.9
docker tag  grafana/grafana:11.6.9 $GRAFANA_MIRROR:11.6.9
docker push $GRAFANA_MIRROR:11.6.9
```

### 3) EKS 클러스터 (eksctl)

```bash
cd eksctl
envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml

# 노드명 확인(채점 4-3): gj2026.<instance_id>.{addon,app}.node 형식이어야 함
kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers
```

### 4) AWS Load Balancer Controller (Addon NodeGroup 배치)

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=gj2026-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 \
  --set vpcId="$VPC_ID" \
  --set nodeSelector.role=addon \
  --set image.repository=${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/eks/aws-load-balancer-controller
# image.tag 는 차트 기본값(appVersion)을 ecr-public pull-through 로 받는다.
```

### 5) Kubernetes 리소스

```bash
cd ../k8s
kubectl apply -f 00-namespaces.yaml
sed "s|<EKS_KMS_KEY_ARN>|$EKS_KMS_KEY_ARN|g" 01-storageclass.yaml | kubectl apply -f -

# book 앱
kubectl apply -f app/configmap.yaml
sed "s|<BOOK_POD_SG_ID>|$BOOK_POD_SG_ID|g" app/securitygrouppolicy.yaml | kubectl apply -f -
sed "s|<ECR_REPOSITORY_URL>|$ECR|g" app/deployment.yaml | kubectl apply -f -
kubectl apply -f app/service.yaml -f app/pdb.yaml
sed "s|<BOOK_TARGET_GROUP_ARN>|$BOOK_TG|g" app/targetgroupbinding.yaml | kubectl apply -f -

# 모니터링 (Grafana + CloudWatch 데이터소스)
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
kubectl -n monitoring create configmap gj2026-dashboard --from-file=dashboard.json=monitoring/dashboard.json
envsubst '${ACCOUNT_ID}' < monitoring/grafana-ecr-images.yaml > /tmp/grafana-ecr.yaml
helm upgrade --install grafana grafana/grafana --version 8.15.0 -n monitoring \
  -f monitoring/grafana-values.yaml -f /tmp/grafana-ecr.yaml
sed "s|<GRAFANA_TARGET_GROUP_ARN>|$GRAFANA_TG|g" monitoring/targetgroupbinding.yaml | kubectl apply -f -

# 로깅 (Fluent Bit, AZ별 로그스트림)
envsubst '${ACCOUNT_ID}' < logging/fluent-bit.yaml | kubectl apply -f -
```

---

## 요구사항 ↔ 구현 매핑

| 요구사항(과제지) | 채점 | 구현 |
|---|---|---|
| 3 Network: private 2 subnet, NAT 0, IGW attach만 | 1-1~1-3 | `vpc.tf`(라우트 local만, NAT 미생성) + `endpoints.tf`(Interface EP only) |
| 5 ECR book, 이미지<3MB | 2-1·2-2 | `ecr.tf` + `app/Dockerfile`(scratch + zstd) |
| 6 DynamoDB books/GSI/CMK/쓰기 제한 | 3-1~3-3 | `dynamodb.tf`(GSI client_id-index + resource policy Deny) |
| 7 EKS 1.35, KMS secret, Bottlerocket, 노드명, 2 NG | 4-1~4-3 | `eksctl/cluster.yaml` + `app/bootstrap/`(hostname-override) |
| 8 book Deployment 2개, ALB만 수신 | 4-4·4-5 | `k8s/app/`(deployment + SecurityGroupPolicy) |
| 9 Load Balancing: internal ALB, /grafana | 5-1 | `alb.tf`(gj2026-alb + book/grafana TG) |
| 10 S3 정적 루트 업로드, CMK | 6-1·6-2 | `s3.tf`(key=루트, SSE-KMS) |
| 11 Lambda gj2026-book-reservation py3.14 | 7-1 | `lambda.tf` + `lambda/index.py` |
| 12 CDN: S3 캐시/ALB·Lambda 무캐시/HTTPS/확장자→index | 8-1~8-4 | `cloudfront.tf` + `cloudfront_function.js` |
| 13 WAF: POST외 405, client_id 정규식 403 | 9-1·9-2 | `waf.tf` |
| 14 Monitoring: Grafana CloudWatch, Fluent Bit AZ분리 | 10-1·10-2 | `k8s/monitoring/` + `k8s/logging/fluent-bit.yaml` + `lambda/index.py`(PutMetricData) |

자세한 설계 근거·함정은 `ARCHITECTURE.md` 참고.
