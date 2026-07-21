# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 (set-03) — 런북

EKS 기반 콘서트 예약(Book) 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 배포한다.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

> 설계 근거는 [deployment.md](../../docs/src/content/docs/setlist/set-03/task-1/deployment.md),
> 요구사항↔구현 매핑은 [mapping.md](../../docs/src/content/docs/setlist/set-03/task-1/mapping.md),
> 주의/함정은 [notes.md](../../docs/src/content/docs/setlist/set-03/task-1/notes.md).


## NOTICE

채점지의 5-5 항목이 클러스터를 `wsi2026-xxxxx` 형식으로 조회하는 오류를 발견 및 임의 수정하였습니다.  
이와 관련한 사항은 마이스터넷에 질의한 상태입니다.

## 디렉토리 구조

```
terraform/   # AWS 인프라 (VPC, KMS×5, DynamoDB, ECR, S3, Lambda, CloudFront, WAF, IAM)
  ├─ providers.tf variables.tf terraform.tfvars data.tf
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
app/                     # 배포파일 위치(book·index.html·main.jpeg) + Dockerfile. step 0 에서 복사
README.linux.md          # 본 PC 가 Linux 일 때의 step 0·1·3·7 명령 (CloudShell 단계 공통)
```

## 배포 순서

### 0) [본 PC·PowerShell] 도구 준비 + 작업용 IAM 사용자 + 사전 변수

```powershell
# root 자격증명으로 1회만 실행
aws iam create-user --user-name wsc2026-admin
aws iam attach-user-policy --user-name wsc2026-admin --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-access-key --user-name wsc2026-admin --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text

# 출력된 키로 프로파일 등록 — CloudShell 단계(2·4)에서도 같은 키를 입력하므로 잘 보관
aws configure --profile wsc2026        # region = ap-northeast-2

# local .env.ps1 — 셸 재시작에도 재사용 (작업 규칙 6, .gitignore 등록됨)
@'
$env:AWS_PROFILE = "wsc2026"
$env:AWS_DEFAULT_REGION = "ap-northeast-2"
'@ | Set-Content .env.ps1
. .\.env.ps1
aws sts get-caller-identity            # arn:...:user/wsc2026-admin 확인

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
terraform output -json | Set-Content ..\outputs.json   # PS7 기본 UTF-8 no BOM → CloudShell jq OK

# CloudShell VPC environment 는 업로드 UI 가 없어 S3 를 릴레이로 쓴다 (_transfer/ 는 step 9 에서 삭제)
$o = Get-Content ..\outputs.json | ConvertFrom-Json
$BUCKET = $o.s3_bucket_name.value
aws s3 cp ..\outputs.json "s3://$BUCKET/_transfer/outputs.json"
tar czf "$env:TEMP\wsc2026-cs.tgz" -C .. k8s
aws s3 cp "$env:TEMP\wsc2026-cs.tgz" "s3://$BUCKET/_transfer/wsc2026-cs.tgz"
```

### 2) [일반 CloudShell] 컨테이너 이미지 빌드 & ECR push (v1.0.0 단일 태그)

> 콘솔에서 **일반 CloudShell**(VPC environment 아님)을 열고 **Actions → Upload file** 로 `app/` 의
> `Dockerfile` 과 `book` 두 파일을 올린다.

```bash
aws configure   # step 0 의 wsc2026-admin 키, region = ap-northeast-2
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
[regex]::Matches($c, '\$\{(\w+)\}') | ForEach-Object { $c = $c.Replace($_.Value, (Get-Item "env:$($_.Groups[1].Value)").Value) }
$c | Set-Content cluster.rendered.yaml
Select-String '\$\{' cluster.rendered.yaml     # 출력이 없어야 함 (치환 누락 검사)

eksctl create cluster -f cluster.rendered.yaml   # 약 20분. 완료 시 자동 private 전환
aws eks describe-cluster --name wsc2026-eks-cluster `
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,endpointPrivateAccess]'   # false, true
# true 로 남았으면:
# aws eks update-cluster-config --name wsc2026-eks-cluster --resources-vpc-config endpointPublicAccess=false
```

### 4) [VPC CloudShell] 환경 생성 + 셋업 (세션 초기화 시 이 블록 재실행)

> 콘솔 CloudShell → **Actions → Create VPC environment** → VPC `wsc2026-skills-vpc`,
> Subnet `wsc2026-skills-app-sub-a`, SG `mark-sg`.

```bash
# ---- VPC CloudShell 셋업 (멱등 — 재접속 시 통째로 재실행) ----
aws configure   # step 0 의 wsc2026-admin 키, region = ap-northeast-2 (terraform 과 동일 신원!)
sudo curl -sLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo chmod +x /usr/local/bin/kubectl
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
mkdir -p ~/wsc2026 && cd ~/wsc2026
aws s3 cp "s3://$BUCKET/_transfer/wsc2026-cs.tgz" . && tar xzf wsc2026-cs.tgz
aws s3 cp "s3://$BUCKET/_transfer/outputs.json" .

cat > ~/.wsc2026-env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export VPC_ID=$(jq -r '.vpc_id.value' outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' outputs.json)
EOF
source ~/.wsc2026-env

aws eks update-kubeconfig --name wsc2026-eks-cluster --region ap-northeast-2
# kubelet clusterDomain 확인 (wsc2026.skills.local)
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq -r .kubeletconfig.clusterDomain
```

### 5) [VPC CloudShell] CoreDNS 내부 도메인 패치 + 기본 k8s 리소스

```bash
cd ~/wsc2026/k8s
kubectl apply -f 00-namespaces.yaml
kubectl apply -f 01-coredns-wsc2026.yaml
kubectl -n kube-system rollout restart deploy/coredns
kubectl -n kube-system rollout status deploy/coredns
# 검증: wsc2026.skills.local 존으로 해석
kubectl run dns-test --rm -it --restart=Never --image=busybox \
  --overrides='{"spec":{"nodeSelector":{"wsc2026/node":"addon"}}}' \
  -- nslookup kubernetes.default.svc.wsc2026.skills.local
```

### 6) [VPC CloudShell] Helm 애드온 + 앱/관측성 리소스

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
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 87.2.1 -n observability -f monitoring/kube-prometheus-stack-values.yaml

# 6-3) App (ECR 치환 → apply)
kubectl apply -f app/00-serviceaccount.yaml -f app/01-configmap.yaml
sed "s|<ECR_REPOSITORY_URL>|$ECR|g" app/02-deployment.yaml | kubectl apply -f -
kubectl apply -f app/03-service.yaml -f app/04-pdb.yaml -f app/05-ingress.yaml

# 6-4) 로깅 + 알람 룰 + 대시보드
kubectl apply -f logging/fluent-bit.yaml
kubectl apply -f monitoring/prometheus-rules.yaml
kubectl create configmap wsc2026-grafana-dashboard -n observability \
  --from-file=dashboard.json=monitoring/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap wsc2026-grafana-dashboard -n observability grafana_dashboard=1 --overwrite

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

### 8) [VPC CloudShell] E2E 검증 + 실측 확인

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

### 9) [VPC CloudShell] 채점 전 정리 (_transfer 제거)

```bash
# S3 릴레이 제거 (static/ 만 남긴다 — mark 6-1)
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
aws s3 rm "s3://$BUCKET/_transfer/" --recursive
```
