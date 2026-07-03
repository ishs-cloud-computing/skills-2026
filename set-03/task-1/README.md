# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 (set-03) — Solution Architecture

EKS 기반 콘서트 예약(Book) 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 구성한 결과물.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준(단, WAF 는 scope=CLOUDFRONT 라 `us-east-1`).
`terraform apply` 는 본 PC, EKS 구성(eksctl/helm/kubectl)은 **작업용 SSM bastion**, 채점은 **CloudShell(mark-sg)** 에서 한다.

## 디렉토리 구조

```
terraform/   # AWS 인프라 (VPC, KMS×5, DynamoDB, ECR, S3, Lambda, CloudFront, WAF, IAM)
  ├─ versions.tf variables.tf terraform.tfvars data.tf
  ├─ vpc.tf security.tf endpoints.tf kms.tf
  ├─ dynamodb.tf ecr.tf s3.tf lambda.tf lambda/index.py
  ├─ cloudfront.tf waf.tf cloudwatch.tf
  └─ iam.tf iam/lbc-policy.json outputs.tf
eksctl/cluster.yaml      # EKS 1.35 fully private, authMode=API, Pod Identity, NG 2개(addon/workload)
k8s/
  ├─ 00-namespaces.yaml 01-coredns-wsc2026.yaml   # ns + 내부 도메인(wsc2026.skills.local) 패치
  ├─ app/         # SA, ConfigMap(book-config), Deployment, Service, PDB, Ingress(ALB)
  ├─ logging/     # Fluent Bit DaemonSet (logfmt → Reference02 JSON + log_to_metrics)
  └─ monitoring/  # kube-prometheus-stack values, PrometheusRule 6종, dashboard.json
app/Dockerfile           # Book App 컨테이너 (alpine + book). book 바이너리는 빌드 시 shared 에서 복사
```

> 제공된 배포파일(`book`, `index.html`, `main.jpeg`)은 repo 공용 `shared/provided/task-1/` 에 있다.
> S3 정적 업로드(`s3.tf`)는 이 경로를 직접 읽고, App 이미지 빌드는 `book` 을 `app/` 로 복사해 쓴다.

## 배포 순서

> **머신 3분할** — ① **본 PC**: `terraform apply`(2회) + 컨테이너 빌드. ② **작업용 SSM bastion**(임시 EC2): eksctl/helm/kubectl.
> ③ **CloudShell**(VPC environment + `mark-sg`): 채점 전용(채점 유의 10·11).
> **모든 CLI 는 terraform 과 같은 자격증명으로 실행한다** — KMS 5키의 관리자 principal 이 배포자 신원뿐이다(유의사항 10: root/kms:* 금지).
> CloudFront/WAF 는 LBC 가 만드는 ALB 에 의존하므로 **terraform 을 2회(1차 → 클러스터/ingress → 2차)** 적용한다.

### 0) [본 PC] 작업용 IAM 사용자 생성 + 사전 변수

> **대회는 root 계정을 지급한다.** 그러나 유의사항 10(키 정책에 root 금지) 때문에 KMS 키의
> 관리자는 IAM 신원이어야 하고, 키를 쓰는 모든 작업(terraform/eksctl/docker push/채점)도
> 그 신원으로 해야 한다. root 는 sts:AssumeRole 호출이 불가하므로 **IAM 사용자 + 액세스 키**
> 를 만들어 이후 모든 단계를 이 신원으로 실행한다. (root 로 apply 하면
> `terraform_data.kms_admin_guard` 가 plan 단계에서 차단한다.)

```bash
# root 자격증명으로 1회만 실행
aws iam create-user --user-name wsc2026-admin
aws iam attach-user-policy --user-name wsc2026-admin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-access-key --user-name wsc2026-admin \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text

# 출력된 키로 프로파일 등록 후 이 신원으로 전환
aws configure --profile wsc2026        # region = ap-northeast-2
export AWS_PROFILE=wsc2026
aws sts get-caller-identity            # arn:...:user/wsc2026-admin 확인

export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=<선수비번호>       # S3 버킷 이름에 사용
export RAND4=<임의영문4자리>  # 예: abcd
```

### 1) [본 PC] Terraform 1차 (네트워크 + AWS 리소스, CDN 제외)

```bash
cd terraform
terraform init
terraform apply -var="player_number=$NUM" -var="bucket_suffix=$RAND4"
terraform output -json > ../outputs.json   # 작업 호스트로 넘길 값 (tfstate 는 넘기지 않는다)

# bastion 은 파일 업로드가 안 되므로 S3 를 릴레이로 쓴다 (_transfer/ 는 채점 전 삭제 — step 10)
BUCKET=$(jq -r '.s3_bucket_name.value' ../outputs.json)
aws s3 cp ../outputs.json "s3://$BUCKET/_transfer/outputs.json"
tar czf /tmp/wsc2026-cs.tgz -C .. eksctl k8s mark.sh
aws s3 cp /tmp/wsc2026-cs.tgz "s3://$BUCKET/_transfer/wsc2026-cs.tgz"
```

> root 자격증명으로는 apply 가 차단된다(키 정책에 root 금지 — `terraform_data.kms_admin_guard`).
> 반드시 step 0 의 `wsc2026-admin` 신원(`AWS_PROFILE=wsc2026`)으로 실행한다.

### 2) [본 PC] 컨테이너 이미지 빌드 & ECR push (v1.0.0 단일 태그)

> **latest 태그 금지** — mark 3-1 이 이미지 태그 목록 `v1.0.0` 단독 출력을 요구한다.

```bash
cd ../app
ECR=$(jq -r '.ecr_repository_url.value' ../outputs.json)
cp ../../../shared/provided/task-1/book ./book   # 제공 바이너리 (수정 금지)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker buildx build --platform linux/amd64 --provenance=false -t "$ECR:v1.0.0" --push .

# scan 완료 / 취약점 0 확인 (요구사항 6)
aws ecr wait image-scan-complete --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0 || \
  { aws ecr start-image-scan --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0; \
    aws ecr wait image-scan-complete --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0; }
aws ecr describe-image-scan-findings --repository-name wsc2026-book-ecr --image-id imageTag=v1.0.0 \
  --query 'imageScanFindings.findingSeverityCounts'   # null/빈 값이어야 함
aws ecr list-images --repository-name wsc2026-book-ecr --query 'imageIds[].imageTag'   # ["v1.0.0"] 만
```

### 3) [본 PC] 작업용 SSM bastion 생성 (임시)

> private 서브넷 EC2 + **`mark-sg` 공유** + SSM 접속(인바운드 0). EKS API(443)는 cp-extra SG 가 `mark-sg` 에 열어두므로 bastion 에서 바로 kubectl 가능. 인스턴스 프로파일은 SSM 전용. **채점 전 삭제**(step 10).

```bash
cd ../terraform
SUBNET=$(jq -r '.private_subnet_ids.value["wsc2026-skills-app-sub-a"]' ../outputs.json)
MARK_SG=$(jq -r '.mark_sg_id.value' ../outputs.json)
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)

aws iam create-role --role-name wsc2026-bastion-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name wsc2026-bastion-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name wsc2026-bastion-profile
aws iam add-role-to-instance-profile --instance-profile-name wsc2026-bastion-profile --role-name wsc2026-bastion-role
sleep 10   # instance profile 전파 대기

BID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.small \
  --iam-instance-profile Name=wsc2026-bastion-profile \
  --subnet-id "$SUBNET" --security-group-ids "$MARK_SG" \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wsc2026-bastion}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "bastion=$BID"

aws ssm start-session --target "$BID"   # 1–2분 후 접속 (session-manager-plugin 필요)
```

### 4) [bastion] 도구 설치 · 자격증명 · 파일 수신 · 환경 변수

```bash
sudo dnf install -y jq tar gzip
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp && sudo install -m755 /tmp/eksctl /usr/local/bin/eksctl
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install -m755 kubectl /usr/local/bin/kubectl
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

aws configure   # step 0 의 wsc2026-admin Access Key/Secret (terraform 과 동일 신원!), region = ap-northeast-2

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
mkdir -p ~/wsc2026 && cd ~/wsc2026
aws s3 cp "s3://$BUCKET/_transfer/wsc2026-cs.tgz" . && tar xzf wsc2026-cs.tgz
aws s3 cp "s3://$BUCKET/_transfer/outputs.json" .

# 환경 변수 — 재접속에도 유지되도록 .bashrc 에 등록 (작업 규칙 6)
cat > ~/.wsc2026-env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export ACCOUNT_ID=$(jq -r '.account_id.value' outputs.json)
export VPC_ID=$(jq -r '.vpc_id.value' outputs.json)
export EKS_KMS_ARN=$(jq -r '.eks_kms_arn.value' outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["wsc2026-skills-app-sub-a"]' outputs.json)
export PRIV_SUBNET_B=$(jq -r '.private_subnet_ids.value["wsc2026-skills-app-sub-b"]' outputs.json)
export CP_EXTRA_SG_ID=$(jq -r '.eks_cp_extra_sg_id.value' outputs.json)
export NODE_SHARED_SG_ID=$(jq -r '.eks_shared_node_sg_id.value' outputs.json)
export BOOK_POD_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.book_pod' outputs.json)
export LBC_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.lbc' outputs.json)
export FLUENTBIT_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.fluentbit' outputs.json)
export GRAFANA_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.grafana' outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' outputs.json)
EOF
grep -qxF 'source ~/.wsc2026-env' ~/.bashrc || echo 'source ~/.wsc2026-env' >> ~/.bashrc
source ~/.wsc2026-env
```

### 5) [bastion] EKS 클러스터 (eksctl)

```bash
cd eksctl
python3 -c 'import os,sys;sys.stdout.write(os.path.expandvars(sys.stdin.read()))' < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml     # 약 20분
aws eks update-kubeconfig --name wsc2026-eks-cluster --region ap-northeast-2

# kubelet clusterDomain 반영 확인 (wsc2026.skills.local 이어야 함)
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq -r .kubeletconfig.clusterDomain
```

> addon 버전은 `eksctl utils describe-addon-versions --kubernetes-version 1.35 --name <addon>` 로 확인 후 cluster.yaml 에 고정한다.

### 6) [bastion] CoreDNS 내부 도메인 패치 + 기본 k8s 리소스

```bash
cd ../k8s
kubectl apply -f 00-namespaces.yaml
kubectl apply -f 01-coredns-wsc2026.yaml
kubectl -n kube-system rollout restart deploy/coredns
kubectl -n kube-system rollout status deploy/coredns
# 검증: wsc2026.skills.local 존으로 해석
kubectl run dns-test --rm -it --restart=Never --image=busybox \
  --overrides='{"spec":{"nodeSelector":{"wsc2026/node":"addon"}}}' \
  -- nslookup kubernetes.default.svc.wsc2026.skills.local
```

### 7) [bastion] Helm 애드온 + 앱/관측성 리소스

```bash
# 7-1) AWS Load Balancer Controller (SA 는 Pod Identity 로 권한 획득)
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.13.4 -n kube-system \
  --set clusterName=wsc2026-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 --set vpcId="$VPC_ID" \
  --set nodeSelector.wsc2026/node=addon

# 7-2) kube-prometheus-stack (release: monitoring — mark 11-1 파드 이름 카운트와 정합)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 87.2.1 -n observability -f monitoring/kube-prometheus-stack-values.yaml

# 7-3) App (ECR 치환 → apply)
kubectl apply -f app/00-serviceaccount.yaml -f app/01-configmap.yaml
sed "s|<ECR_REPOSITORY_URL>|$ECR|g" app/02-deployment.yaml | kubectl apply -f -
kubectl apply -f app/03-service.yaml -f app/04-pdb.yaml -f app/05-ingress.yaml

# 7-4) 로깅 + 알람 룰 + 대시보드
kubectl apply -f logging/fluent-bit.yaml
kubectl apply -f monitoring/prometheus-rules.yaml
kubectl create configmap wsc2026-grafana-dashboard -n observability \
  --from-file=dashboard.json=monitoring/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap wsc2026-grafana-dashboard -n observability grafana_dashboard=1 --overwrite

# ALB 프로비저닝 확인 (2차 terraform 의 data.aws_lb 조건)
kubectl get ingress -n wsc2026    # ADDRESS 에 wsc2026-app-alb-...elb.amazonaws.com
aws elbv2 describe-load-balancers --names wsc2026-app-alb --query 'LoadBalancers[0].State.Code'   # active
```

### 8) [본 PC] Terraform 2차 (CloudFront / WAF / 버킷 정책 / Lambda permission)

```bash
cd terraform
terraform apply -var="player_number=$NUM" -var="bucket_suffix=$RAND4" -var="enable_cdn=true"
terraform output -raw cloudfront_domain    # 이후 $CF 로 사용
```

### 9) [bastion] E2E 검증 + 실측 확인

```bash
CF=<cloudfront_domain>   # step 8 출력
# 루트(정적 페이지) 200
curl -s -o /dev/null -w '%{http_code}\n' "https://$CF/"
# POST /booking → booking_id
BID_RESP=$(curl -s -X POST "https://$CF/booking" -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2025"}')
echo "$BID_RESP"
BOOKING_ID=$(echo "$BID_RESP" | jq -r .booking_id)
# GET /v1/book — 필드 순서(client_id,username,email,concert_name,created_at)와 KST 포맷 확인 (mark 9-3)
curl -s "https://$CF/v1/book?booking_id=$BOOKING_ID"
# created_at 저장 원본 포맷 실측 (lambda/index.py 가 다형 파싱하지만 눈으로 확인)
aws dynamodb scan --table-name wsc2026-book-table --max-items 1 --query 'Items[0].created_at'

# 로그 기반 메트릭 실명 확인 (prometheus-rules/dashboard 의 메트릭 이름과 대조)
FB_POD=$(kubectl get pods -n observability -l app=fluent-bit -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n observability "$FB_POD" -- curl -s localhost:2021/metrics | grep -o '^log_metric[a-z_0-9]*' | sort -u

# Grafana LB / datasource / 대시보드 (mark 11-2)
GRAFANA_LB=$(kubectl get svc -n observability monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -u admin:'Skills$#$@!' "http://$GRAFANA_LB/api/datasources" | jq -r '.[].name'   # alertmanager cloudwatch prometheus
curl -s -u admin:'Skills$#$@!' "http://$GRAFANA_LB/api/search?query=wsc2026" | jq -r '.[].title'

# CloudWatch 앱 로그 (Reference02 형식: INFO  {"level":...,"method":...})
aws logs tail /wsc2026/eks/book-app --since 10m | head -5
```

### 10) [본 PC] 채점 전 정리

```bash
BID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=wsc2026-bastion Name=instance-state-name,Values=running \
  --query "Reservations[].Instances[].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids "$BID"
aws ec2 wait instance-terminated --instance-ids "$BID"
aws iam remove-role-from-instance-profile --instance-profile-name wsc2026-bastion-profile --role-name wsc2026-bastion-role
aws iam delete-instance-profile --instance-profile-name wsc2026-bastion-profile
aws iam detach-role-policy --role-name wsc2026-bastion-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name wsc2026-bastion-role

# S3 릴레이 제거 (static/ 만 남긴다 — mark 6-1)
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
aws s3 rm "s3://$BUCKET/_transfer/" --recursive
```

### 11) [CloudShell] 채점

1. 콘솔 CloudShell → **Actions → Create VPC environment** → VPC `wsc2026-skills-vpc`, Subnet `wsc2026-skills-app-sub-a`, SG `mark-sg` (채점 유의 11).
2. ```bash
   BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
   # 채점 전 _transfer 가 남아 있으면 step 10 을 먼저 수행
   aws s3 cp "s3://$BUCKET/_transfer/wsc2026-cs.tgz" /tmp/ 2>/dev/null && tar xzf /tmp/wsc2026-cs.tgz -C /tmp mark.sh && cp /tmp/mark.sh ~/ || true
   aws eks update-kubeconfig --name wsc2026-eks-cluster --region ap-northeast-2
   bash ~/mark.sh
   ```
   > mark.sh 를 S3 릴레이로 받을 수 없으면(이미 정리함) 레포에서 복사해 붙여넣는다.
   > 채점 셸 신원이 클러스터 생성자와 다르면 access entry 추가 + **KMS 채점(check_kms)이 키 조회 권한 부족으로 실패할 수 있으므로** 같은 신원 사용을 권장.

## 리소스 정리 유의사항

- DynamoDB 삭제 방지 해제(`deletion_protection_enabled=false` 로 apply) 후 destroy.
- S3 는 `force_destroy` 미설정 — 객체(정적 파일·릴레이) 비운 후 destroy.
- CloudFront 비활성→삭제에 시간이 걸린다(2차 apply 리소스부터 역순 destroy 권장).

---

## 요구사항 ↔ 구현 매핑 (mark.sh 기준)

| mark | 검사 항목 | 구현 |
|------|----------|------|
| 1-1/1-2 | VPC·서브넷 이름/CIDR, IGW/NAT/RTB 매핑 | `vpc.tf` (Reference01 그대로, 변수화) |
| 2-1 | PK client_id, GSI booking_id, PPR, SSE-KMS, 삭제방지, PITR 35일, 리소스 정책 2건, db-kms | `dynamodb.tf`, `kms.tf` |
| 3-1 | scanOnPush, MUTABLE_WITH_EXCLUSION+`v1*`, KMS, 태그 v1.0.0 단독 | `ecr.tf`, step 2 (latest 금지) |
| 4-1 | 1.35, private, 전체 로그, 클러스터 SG any-open 없음, CoreDNS 도메인, eks-kms | `eksctl/cluster.yaml`, `k8s/01-coredns-wsc2026.yaml` |
| 4-2 | NG 2개 이름/타입/라벨/노드 2대씩 | `eksctl/cluster.yaml` |
| 4-3 | 세 롤에 AdministratorAccess 없음 | eksctl 기본 최소 롤 |
| 5-1 | deploy 2/2, svc, ingress ALB DNS, PDB minAvailable 1 | `k8s/app/*` |
| 5-2 | replicas/nodeSelector/topologySpread/250m/512Mi | `k8s/app/02-deployment.yaml` |
| 5-3 | probe 3종 /health:8080, book-config 데이터 | `k8s/app/01-configmap.yaml`, `02-deployment.yaml` |
| 5-4 | 앱 파드가 application 노드에만 | nodeSelector + workload NG taint |
| 5-5 | Pod Identity SA/역할 정책 | `cluster.yaml` association + `iam.tf` **관리형** 정책 |
| 6-1 | 버킷명/퍼블릭차단4/SSE-KMS+BucketKey/static 객체별 KMS | `s3.tf` (`static/` 마커 포함) |
| 7-1 | python3.12, TABLE_NAME 암호문(AQICAH...), function-kms | `lambda.tf` (`aws_kms_ciphertext`) |
| 7-2 | 역할/정책 이름, Query 포함·Action 에 `*` 없음 | `iam.tf` (BasicExecutionRole 미부착, logs 액션 명시) |
| 8-1 | internet-facing, SG 이름 단독, 직접 curl 차단(000) | `k8s/app/05-ingress.yaml` + `security.tf`(CF prefix list) |
| 9-1 | CF 도메인 200 (루트 정적 페이지) | `cloudfront.tf` (origin_path=/static) |
| 9-2 | S3 CachingOptimized / ALB·Lambda CachingDisabled | `cloudfront.tf` (관리형 정책 ID) |
| 9-3 | POST /booking → GET /v1/book 필드순서+KST | CloudFront Function rewrite + `lambda/index.py` |
| 10-1 | WAF 이름, SQLi/XSS 403, rate Limit≤200 | `waf.tf` (커스텀 sqli/xss + rate 200/60s) |
| 11-1 | observability 에 fluent-bit/prometheus/grafana Running, Grafana LB | `k8s/logging/fluent-bit.yaml`, kps values |
| 11-2 | datasource 3개 이름·타입, 대시보드 wsc2026-grafana-dashboard | kps values, `dashboard.json` |
| 11-3 | 대시보드 Row 5종 + 로그 형식 | `dashboard.json`, fluent-bit `format.lua` |
| 11-4 | 알람 5종 Firing | `prometheus-rules.yaml` + log_to_metrics (아래 주의) |

## 주의 / 알려진 한계

- **mark 5-5 스크립트 오타**: `aws eks list-pod-identity-associations --cluster-name wsi2026-cluster` —
  실제 클러스터는 `wsc2026-eks-cluster` 이므로 스크립트 그대로는 항상 FAIL 이다. 구현은 실제 클러스터에
  정상 구성되어 있으며(`aws eks list-pod-identity-associations --cluster-name wsc2026-eks-cluster --namespace wsc2026` 로 확인),
  채점 시 이의제기 근거로 사용한다.
- **11-4 HighLatency 실발화 불가**: 제공 book 바이너리에 `/delay` 엔드포인트가 없다(로컬 실측 — 404, µs 응답).
  채점 스크립트의 latency-gen 으로는 평균 응답 3초 초과를 만들 수 없다. 룰은 사양(3s/1m)대로 구현했고,
  대회 당일 바이너리에 /delay 가 있으면 그대로 동작한다. 나머지 알람(PodHighCPU/PodHighMemory/PodNotReady/
  HighErrorRate/PodCrashLooping)은 채점 스크립트의 부하 파드로 발화된다.
- **KMS root/kms:* 금지(유의 10)**: 5키 모두 배포자 신원(`aws_iam_session_context`) + 서비스별 최소 statement.
  **대회 지급 계정은 root 이므로 step 0 에서 IAM 사용자(wsc2026-admin)를 만들고,
  terraform/eksctl/docker push/kubectl/채점을 전부 그 신원으로** 실행한다.
  root 로는 KMS 사용은 물론 alias 생성·CMK 테이블/객체 생성도 전부 거부된다(키 정책이 유일한 통제).
  다른 관리자를 추가하려면 `kms_extra_admin_arns` 변수 사용. root 자격증명은 plan 단계에서 차단된다.
- **HTTP 메트릭은 로그 기반**: 앱이 /metrics 를 노출하지 않아 fluent-bit `log_to_metrics` 필터가
  액세스 로그에서 requests/errors counter 와 duration histogram 을 생성한다(`:2021/metrics`).
  배포 후 step 9 에서 **메트릭 실명을 확인**하고 `prometheus-rules.yaml`/`dashboard.json` 의
  `log_metric_counter_wsc2026_*` 이름과 다르면 맞춘다. aws-for-fluent-bit 이미지에 log_to_metrics 가
  없으면 upstream `fluent/fluent-bit` 최신 안정 태그로 교체(fallback).
- **ALB SG 단독 부착**: ingress 의 `security-groups` 어노테이션에 `wsc2026-app-alb-sg` 만 지정하고
  `manage-backend-security-group-rules` 는 쓰지 않는다(mark 8-1 이 SG 이름 단독 출력 요구).
  ALB→Pod 8080 은 Terraform `wsc2026-eks-shared-node-sg`(노드 attachIDs)가 사전 허용한다.
- **CoreDNS 도메인**: kubelet clusterDomain(eksctl `overrideBootstrapCommand`의 nodeadm NodeConfig)과
  CoreDNS Corefile 패치가 **모두** 적용돼야 파드 DNS 가 정상 동작한다. coredns addon 업데이트 시
  Corefile 이 초기화될 수 있으므로 업데이트 금지, 했다면 재적용 후 mark 4-1 grep 재확인.
- **CloudFront /booking**: 앱은 POST `/v1/book` 만 제공 — CloudFront Function(viewer-request)이
  `/booking` → `/v1/book` 으로 rewrite 한다. ALB 는 경로 rewrite 가 불가하다.
- **Lambda 환경변수**: `TABLE_NAME` 값 자체가 KMS 암호문(`aws_kms_ciphertext`)이고 코드가 런타임에
  복호화한다(전송 중 암호화). `kms_key_arn` 은 저장 시 암호화. 두 가지 모두 wsc2026-function-kms.
- **이미지 풀**: app 서브넷에 NAT 가 있어 공개 레지스트리(LBC/kps/fluent-bit)는 직접 pull.
  eks/eks-auth Interface Endpoint 는 만들지 않는다(PHZ 가 Pod Identity 를 깨는 함정 — `endpoints.tf` 주석).
