# set-02 / 제1과제 — wskorea26 Concert Platform (Linux/bash 런북)

> 대회 PC 는 Windows 이므로 **주 런북은 [README.md](./README.md) (PowerShell)** 다.
> 이 파일은 리눅스 개발 환경용 bash 런북을 보존한 것이다. 명령만 다르고 리소스/순서는 동일하다.

CloudFront + S3(정적 웹) + EKS(book 앱) + Lambda(예매 조회) + DynamoDB + 모니터링(Grafana)을
**Terraform / eksctl / Kubernetes manifest** 로 구성한다. 모든 리소스는 서울(`ap-northeast-2`).

## 디렉토리 구조

```
terraform/                 # AWS 인프라 (VPC, SG, KMS, S3, ECR, DynamoDB, Lambda, ALB, CloudFront, IAM)
  ├─ versions.tf  variables.tf  terraform.tfvars  data.tf
  ├─ vpc.tf  security.tf  kms.tf
  ├─ s3.tf  ecr.tf  dynamodb.tf
  ├─ lambda.tf  lambda/index.py
  ├─ alb.tf  cloudfront.tf  cloudfront/book-rewrite.js
  ├─ iam.tf  iam/lbc-policy.json  cloudwatch.tf  outputs.tf
eksctl/
  └─ cluster.yaml          # EKS 1.35 + addon/app Managed NodeGroup + IRSA
k8s/
  ├─ 00-namespaces.yaml
  ├─ app/                  # ConfigMap, Deployment, Service, PDB, TargetGroupBinding
  └─ monitoring/           # kube-prometheus-stack values, dashboard, Grafana TGB, Fluent Bit
app/
  └─ Dockerfile            # 제공 book 바이너리 래핑 (alpine 고정 버전 + tzdata)
```

제공자료(`book`, `index.html`, `main.jpeg`)는 `../../shared/provided/task-1/` 를 수정 없이 그대로 사용한다.

## 배포 순서 (모두 본 PC 에서 실행)

### 0) 준비

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=<비번호>            # 예: 103
cd set-02/task-1
```

### 1) Terraform

```bash
cd terraform
terraform init
terraform apply -var="player_number=$NUM"
```

**작업 변수 영구화 (`set-02/task-1/.env`)** — 이후 모든 단계가 이 변수를 재사용한다.
터미널이 바뀌어도 이어서 작업할 수 있게 파일로 박아둔다 (cwd = `terraform`):

```bash
terraform output -json > ../outputs.json

cat > ../.env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=$NUM
export ACCOUNT_ID=$(terraform output -raw account_id)
export VPC_ID=$(terraform output -raw vpc_id)
export PRIV_SUBNET_C=$(terraform output -json private_subnet_ids | jq -r '."wskorea26-priv-subnet-c"')
export PRIV_SUBNET_D=$(terraform output -json private_subnet_ids | jq -r '."wskorea26-priv-subnet-d"')
export CLUSTER_EXTRA_SG_ID=$(terraform output -raw cluster_extra_sg_id)
export NODE_SG_ID=$(terraform output -raw node_sg_id)
export EKS_KMS_ARN=$(terraform output -raw eks_kms_arn)
export BOOK_APP_POLICY_ARN=$(terraform output -raw book_app_policy_arn)
export LBC_POLICY_ARN=$(terraform output -raw lbc_policy_arn)
export FLUENT_BIT_POLICY_ARN=$(terraform output -raw fluent_bit_policy_arn)
export ECR=$(terraform output -raw ecr_repository_url)
export APP_TG=$(terraform output -raw app_target_group_arn)
export GRAFANA_TG=$(terraform output -raw grafana_target_group_arn)
export BUCKET=$(terraform output -raw s3_bucket_name)
export ALB_DNS=$(terraform output -raw book_alb_dns)
export GRAFANA_ALB_DNS=$(terraform output -raw grafana_alb_dns)
export CF=$(terraform output -raw cloudfront_domain)
EOF

source ../.env   # 새 터미널로 이어서 할 땐 task-1 에서 `source .env` 만 다시 실행
```

### 2) 컨테이너 이미지 빌드 & ECR push (태그 `stable`) — 기본 CloudShell

로컬엔 Docker 가 없으므로 빌드는 **기본 CloudShell**(인터넷 O, docker 내장)에서 한다.
VPC CloudShell(§9)은 인터넷이 없어 alpine 베이스를 못 받으니 쓰지 않는다.
`shared/provided/task-1/book` 과 `app/Dockerfile` 을 **Actions → Upload file** 로 올린다(홈 `~` 에 저장). 빌드 블록은 모든 플랫폼 동일하다:

```bash
# [기본 CloudShell] — book, Dockerfile 업로드 후
export AWS_DEFAULT_REGION=ap-northeast-2
ECR=$(aws ecr describe-repositories --repository-names wskorea26-book-repo --query 'repositories[0].repositoryUri' --output text)
mkdir -p ~/build && mv ~/book ~/Dockerfile ~/build/ && cd ~/build
aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:stable" .   # CloudShell=amd64 네이티브, 단일아키(스캔 호환)
docker push "$ECR:stable"

# 스캔 완료 대기 후 Critical/High 없는지 확인 (mark 3-1)
aws ecr wait image-scan-complete --repository-name wskorea26-book-repo --image-id imageTag=stable || \
  { aws ecr start-image-scan --repository-name wskorea26-book-repo --image-id imageTag=stable; \
    aws ecr wait image-scan-complete --repository-name wskorea26-book-repo --image-id imageTag=stable; }
aws ecr describe-image-scan-findings --repository-name wskorea26-book-repo --image-id imageTag=stable \
  --query 'imageScanFindings.findingSeverityCounts'   # CRITICAL/HIGH 키가 없어야 함
```

### 3) EKS 클러스터 (eksctl)

```bash
cd eksctl
envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml     # 약 20분

aws eks update-kubeconfig --region ap-northeast-2 --name wskorea26-cluster
kubectl get nodes --show-labels | grep node-type   # addon/app 라벨 확인
```

> addon 버전은 `eksctl utils describe-addon-versions --kubernetes-version 1.35 --name <addon>` 로
> 재확인 후 cluster.yaml 의 핀을 갱신한다 (latest 금지 — 작업규칙 2).
>
> **생성 중단 시 부분 복구**: OIDC `eksctl utils associate-iam-oidc-provider --cluster wskorea26-cluster --approve` ·
> IAM SA `eksctl create iamserviceaccount -f cluster.rendered.yaml --approve` ·
> NodeGroup `eksctl create nodegroup -f cluster.rendered.yaml --include=<ng>` ·
> Addon `eksctl create addon -f cluster.rendered.yaml`

### 4) AWS Load Balancer Controller (TargetGroupBinding 용)

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 3.4.0 \
  -n kube-system \
  --set clusterName=wskorea26-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 \
  --set vpcId="$VPC_ID" \
  --set nodeSelector.node-type=addon
```

### 5) Book 애플리케이션 (k8s)

```bash
cd ../k8s
kubectl apply -f 00-namespaces.yaml
kubectl apply -f app/configmap.yaml
sed "s|<ECR_REPOSITORY_URL>|$ECR|g" app/deployment.yaml | kubectl apply -f -
kubectl apply -f app/service.yaml -f app/pdb.yaml
sed "s|<APP_TARGET_GROUP_ARN>|$APP_TG|g" app/targetgroupbinding.yaml | kubectl apply -f -

# 타겟 healthy 대기
aws elbv2 wait target-in-service --target-group-arn "$APP_TG"
```

### 6) 모니터링 (kube-prometheus-stack + Grafana)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update

# Grafana 계정 치환: skills-<비번호>-admin / $korea26!! (mark 10)
sed -e "s|<GRAFANA_ADMIN_USER>|skills-${NUM}-admin|" \
    -e 's|<GRAFANA_ADMIN_PASSWORD>|$korea26!!|' \
    monitoring/kube-prometheus-stack-values.yaml > /tmp/kps-values.yaml

helm upgrade --install wskorea26-monitoring prometheus-community/kube-prometheus-stack \
  --version 87.5.1 -n monitoring -f /tmp/kps-values.yaml

# 대시보드 provisioning (uid=wskorea26, title=wskorea26-monitoring)
kubectl -n monitoring create configmap wskorea26-dashboard \
  --from-file=dashboard.json=monitoring/dashboard.json
kubectl -n monitoring label configmap wskorea26-dashboard grafana_dashboard=1

# Grafana ALB 연결
sed "s|<GRAFANA_TARGET_GROUP_ARN>|$GRAFANA_TG|g" monitoring/grafana-targetgroupbinding.yaml | kubectl apply -f -
aws elbv2 wait target-in-service --target-group-arn "$GRAFANA_TG"
```

### 7) 로깅 (Fluent Bit → CloudWatch Logs)

```bash
kubectl apply -f monitoring/fluent-bit.yaml
kubectl -n monitoring get ds fluent-bit   # DESIRED = 노드 수
```

### 8) 검증 시드 (mark 순서대로)

```bash
# CloudFront 배포 완료 대기 (mark 8-1 은 Status=Deployed 를 검사)
CF_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='wskorea26-concert-cf'].Id | [0]" --output text)
aws cloudfront wait distribution-deployed --id "$CF_ID"

curl -o /dev/null -s -w "%{http_code}\n" "https://$CF"            # 200 (정적 웹)
curl -o /dev/null -s -w "%{http_code}\n" "http://$CF/"            # 301 (HTTPS 리다이렉트)
curl -o /dev/null -s -w "%{size_download}\n" "https://$CF/main.jpeg"  # 180926
curl -o /dev/null -s -w "%{http_code}\n" "http://$ALB_DNS/book"   # 403 (CloudFront 미경유)

curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"client_id":"T0001","username":"tester","email":"t@t.com","concert_name":"SEED_CON"}' \
  "https://$CF/book"                                              # {"booking_id": "..."}
curl -s "https://$CF/book?concert_name=SEED_CON"                  # 최신순 배열
curl -o /dev/null -s -w "%{http_code}\n" "https://$CF/book"       # 400 (파라미터 없음)

echo "Grafana: http://$GRAFANA_ALB_DNS/d/wskorea26/wskorea26-monitoring"
echo "Login  : skills-${NUM}-admin / \$korea26!!"
```

### 9) 채점 준비 (CloudShell VPC Environment)

채점 항목 0: CloudShell VPC Environment 를 **Subnet `wskorea26-priv-subnet-d` + SG
`wskorea26-vpc-environment-sg`** 로 생성해 접속한다. VPC CloudShell 은 파일 업로드가
안 되지만 터미널 붙여넣기는 되므로 mark.sh 는 heredoc 으로 붙여넣는다:

```bash
# [CloudShell VPC Environment]
rm -rf ~/.aws && aws configure   # default region: ap-northeast-2
cat > ~/mark.sh <<'MARKEOF'
# ← 본 PC 의 mark.sh 내용을 그대로 붙여넣기
MARKEOF
chmod +x ~/mark.sh
```

### 10) 정리 (대회 종료 후)

```bash
cd set-02/task-1   # 과제 루트에서 실행
helm -n monitoring uninstall wskorea26-monitoring
helm -n kube-system uninstall aws-load-balancer-controller
eksctl delete cluster -f eksctl/cluster.rendered.yaml --disable-nodegroup-eviction
# DynamoDB 삭제방지 해제 후 destroy
aws dynamodb update-table --table-name wskorea26-data-table --no-deletion-protection-enabled
cd terraform && terraform destroy -var="player_number=$NUM"
```

---

## 요구사항 ↔ 구현 매핑

| # | 요구사항 (mark) | 구현 |
|---|---|---|
| 3 | VPC/서브넷 CIDR, RTB/IGW/NAT (1-1, 1-2) | `terraform/vpc.tf` (`book-igw`, `book-ngw-c/d`, RTB 3개) |
| 4 | S3 web/main 객체, SSE-KMS, 퍼블릭 차단 (2-1, 2-2) | `terraform/s3.tf` + `kms.tf`(`wskorea26-s3-key`) |
| 5 | book 앱 실행 (9-1~9-4) | `app/Dockerfile`, `k8s/app/*`, CloudFront Function(경로 재작성) |
| 6 | ECR 스캔/KMS/`stable` 태그 (3-1) | `terraform/ecr.tf` + 배포 순서 2) |
| 7 | DynamoDB PK/삭제방지/KMS (4-1) | `terraform/dynamodb.tf` (+ GSI `concert_name-created_at-index`) |
| 8 | EKS 1.35, 로그 5종, KMS, priv 서브넷, NG 2개, ns (5-1~5-4) | `eksctl/cluster.yaml`, `k8s/00-namespaces.yaml` |
| 9 | Lambda python3.14, TABLE_NAME, 최소권한 (6-1) | `terraform/lambda.tf` + `lambda/index.py` |
| 10 | ALB internet-facing/80, 헤더 규칙 2개 + 403 (7-1, 7-2) | `terraform/alb.tf` |
| 11 | CF Comment/Origin/정책/커스텀 헤더/정적 웹 (8-1~8-5) | `terraform/cloudfront.tf` + `cloudfront/book-rewrite.js` |
| 12 | Grafana 대시보드/ALB, 메트릭+로그 수집 (10-1~10-4) | `k8s/monitoring/*`, `terraform/alb.tf`(grafana), `cloudwatch.tf` |
| 유의 13 | `wskorea26-vpc-environment-sg` → EKS 접근 | `terraform/security.tf` + `eksctl vpc.securityGroup` |

## 설계 근거

- **GET /book → Lambda, POST /book → 앱**: 제공 book 바이너리는 `POST /v1/book`·`GET /health` 만
  서빙한다(수정 금지). 채점은 `https://<CF>/book` 으로 POST/GET 을 모두 시험하므로,
  CloudFront Function(`book-rewrite.js`)이 **POST 일 때만** `/book`→`/v1/book` 으로 재작성해
  앱으로 보내고, GET 은 ALB 리스너 규칙이 Lambda TG 로 보낸다. viewer-request 단계의
  URI 재작성은 cache behavior 를 다시 매칭하지 않으므로 오리진은 그대로 ALB 다.
- **ALB 리스너 규칙은 정확히 2개**: mark 7-2 가 `HttpHeaderConfig.Values[]` 출력으로
  `wskorea26-cf` **2줄**을 기대한다. 규칙 추가/삭제 금지 (`terraform/alb.tf` 주석 참고).
- **IRSA (Pod Identity 미사용)**: mark 5-4 는 kube-system 파드(aws-node/kube-proxy 제외)가
  모두 addon 노드에 있길 요구한다. Pod Identity 는 `eks-pod-identity-agent` DaemonSet 이
  전 노드(app 포함)에 떠서 위반. 같은 이유로 **EBS CSI 미설치**(Prometheus 는 emptyDir,
  retention 6h), **eksctl 기본 addon 자동설치 비활성**(metrics-server 차단), coredns 는
  `configurationValues` 로 addon 노드 고정, LBC 도 `nodeSelector.node-type=addon`.
- **EKS 엔드포인트 public+private**: bastion EC2 를 만들면 유의사항 10(불필요 리소스 감점)
  위반이므로 본 PC(public 엔드포인트)에서 kubectl/helm 을 수행한다. "Private 환경" 요구는
  채점상 클러스터/노드 서브넷(priv-c/d)으로 충족되며(mark 5-2/5-3), 채점 CloudShell 은
  private 엔드포인트(+`wskorea26-cluster-extra-sg` 443 인바운드)로 접근한다.
  당일 private-only 가 강제되면 `clusterEndpoints.publicAccess: false` 로 바꾸고
  3)~8) 단계를 CloudShell VPC Environment 에서 수행한다.
- **DynamoDB GSI**: Reference03 의 "데이터베이스 레벨 최신순 정렬" 은 테이블 PK(client_id)만으론
  불가능 → GSI(`concert_name` HASH, `created_at` RANGE) + `ScanIndexForward=False` Query.
- **Dockerfile 베이스 alpine 고정**: ECR Basic 스캔은 scratch 이미지를 스캔하지 못한다.
  alpine 은 CA 번들 기본 포함(DynamoDB TLS), `tzdata`+`TZ=Asia/Seoul` 로 created_at KST 보장.
- **Fluent Bit 만 전 노드 DaemonSet**: Pod 로그 파일은 노드 로컬에만 있어 app 노드 수집이
  불가피하다. mark 5-4 는 kube-system/wskorea26 만 검사하므로 채점 영향 없음
  (manifest 주석 참고).

## 주의 / 함정

- **비번호(`player_number`)**: `terraform.tfvars` 기본 103. 반드시 본인 번호로 교체
  (버킷 이름 + Grafana 계정에 사용).
- **Grafana 비밀번호 `$korea26!!`**: 셸에서 반드시 **작은따옴표**로 감쌀 것
  (`$`, `!` 확장 방지). 배포 순서 6) 의 sed 명령이 그 형태다.
- **ECR 스캔**: 당일 alpine 패치 상태에 따라 결과가 달라질 수 있다. 기준은
  "Critical/High 없음"(mark 3-1 비고). High 가 나오면 Dockerfile 에
  `RUN apk upgrade --no-cache` 를 추가해 재빌드/재푸시한다.
- **채점 대상 필드 유지**: ALB 규칙 2개의 헤더 조건, CF 커스텀 헤더 2개
  (`X-Origin-Verify`, `wskorea26-s3-access`), 노드그룹 `tags.Name` 은 중복돼 보여도
  제거 금지 (작업규칙 4).
- **CloudFront 전파**: apply 후 Deployed 까지 수 분 소요. mark 전 8) 의
  `wait distribution-deployed` 로 확인.
- **eksctl/helm 옵션 드리프트**: `clusterEndpoints`·`addonsConfig.disableDefaultAddons`·
  `instanceName` 등은 버전 따라 바뀔 수 있으니 사용 전 공식 문서로 확인 (작업규칙 7).
