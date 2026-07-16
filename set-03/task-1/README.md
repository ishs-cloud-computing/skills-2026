# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 (set-03) — Solution Architecture

EKS 기반 콘서트 예약(Book) 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 구성한 결과물.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준(단, WAF 는 scope=CLOUDFRONT 라 `us-east-1`).
`terraform`·`eksctl` 은 **본 PC(Windows PowerShell)**, 컨테이너 빌드는 **일반 CloudShell**,
kubectl/helm 작업과 채점은 **CloudShell VPC environment(`mark-sg`)** 에서 한다.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

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
app/                     # 배포파일 위치(book·index.html·main.jpeg) + Dockerfile. 런북 step 0 에서 복사
README.linux.md          # 본 PC 가 Linux 일 때의 step 0·1·3·7 명령 (CloudShell 단계는 본 문서 공통)
```

> 제공된 배포파일(`book`, `index.html`, `main.jpeg`)의 원본은 repo 공용 `shared/provided/task-1/` 에 있고
> (수정 금지), 런북 step 0 에서 이를 이 과제의 `app/` 로 복사한다.
> S3 정적 업로드(`s3.tf`)는 `app/` 를 직접 읽고, App 이미지 빌드도 `app/` 의 `book` 을 쓴다.

## 배포 순서

> **머신 2분할** — ① **본 PC**(Windows PowerShell): `terraform apply`(2회) + `eksctl create cluster`.
> ② **CloudShell**: 컨테이너 빌드는 **일반 CloudShell**(step 2), kubectl/helm 작업·E2E·채점은
> **VPC environment**(`mark-sg` — 채점 유의 10·11과 동일 환경, step 4~9).
> **모든 CLI 는 terraform 과 같은 자격증명(wsc2026-admin)으로 실행한다** — KMS 5키의 관리자 principal 이 배포자 신원뿐이다(유의사항 10: root/kms:* 금지).
> CloudFront/WAF 는 LBC 가 만드는 ALB 에 의존하므로 **terraform 을 2회(1차 → 클러스터/ingress → 2차)** 적용한다.
> fully-private 클러스터여도 eksctl 은 생성 중 퍼블릭 엔드포인트를 임시로 켰다가 완료 시 닫으므로
> **생성은 본 PC 에서 가능**하다(eksctl 공식 문서 Limitations). 생성 이후 K8s API 작업(kubectl/helm/채점)은 VPC 안에서만 된다.

### 0) [본 PC·PowerShell] 도구 준비 + 작업용 IAM 사용자 + 사전 변수

> **필요 도구**: AWS CLI v2(msi) · Terraform · eksctl (zip 해제 → PATH 등록). `tar`·`curl` 은
> Windows 10+ 기본 내장, jq 불필요(`ConvertFrom-Json` 내장), **Docker 불필요**(빌드는 step 2 일반 CloudShell).
> 본 PC 는 기본 미설치 + 재시동 시 초기화(CLAUDE.md 환경)이므로 매 세션 준비한다.

> **대회는 root 계정을 지급한다.** 그러나 유의사항 10(키 정책에 root 금지) 때문에 KMS 키의
> 관리자는 IAM 신원이어야 하고, 키를 쓰는 모든 작업(terraform/eksctl/docker push/채점)도
> 그 신원으로 해야 한다. root 는 sts:AssumeRole 호출이 불가하므로 **IAM 사용자 + 액세스 키**
> 를 만들어 이후 모든 단계를 이 신원으로 실행한다. (root 로 apply 하면
> `terraform_data.kms_admin_guard` 가 plan 단계에서 차단한다.)

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
'@ | Set-Content .env.ps1 -Encoding Ascii
. .\.env.ps1
aws sts get-caller-identity            # arn:...:user/wsc2026-admin 확인

# 배포파일을 이 과제의 app/ 로 복사 — s3.tf 와 이미지 빌드가 app/ 를 직접 읽는다 (원본은 shared, 수정 금지)
Copy-Item ..\..\shared\provided\task-1\* .\app\

# 대회 당일 바뀌는 값은 tfvars 로 — 1·2차 apply 가 같은 값을 쓴다 (-var 재입력 금지)
# player_number = 선수 비번호(S3 버킷 이름에 사용), bucket_suffix = 소문자 영문 4자리(예: abcd)
# 주의: 한글 주석을 넣으면 PS5.1 이 CP949 로 저장해 terraform 이 invalid UTF-8 로 실패한다
@'
player_number = "00"
bucket_suffix = "abcd"
'@ | Set-Content terraform\terraform.tfvars -Encoding Ascii
```

### 1) [본 PC·PowerShell] Terraform 1차 (네트워크 + AWS 리소스, CDN 제외)

```powershell
cd terraform
terraform init
terraform apply
# 주의: PS5.1 의 `>` 리다이렉트는 UTF-16 으로 저장돼 CloudShell 의 jq 가 못 읽는다 — Ascii 명시
terraform output -json | Set-Content ..\outputs.json -Encoding Ascii

# CloudShell VPC environment 는 파일 업로드 UI 가 없어 S3 를 릴레이로 쓴다 (_transfer/ 는 채점 전 삭제 — step 9)
$o = Get-Content ..\outputs.json | ConvertFrom-Json
$BUCKET = $o.s3_bucket_name.value
aws s3 cp ..\outputs.json "s3://$BUCKET/_transfer/outputs.json"
tar czf "$env:TEMP\wsc2026-cs.tgz" -C .. k8s mark.sh
aws s3 cp "$env:TEMP\wsc2026-cs.tgz" "s3://$BUCKET/_transfer/wsc2026-cs.tgz"
```

> root 자격증명으로는 apply 가 차단된다(키 정책에 root 금지 — `terraform_data.kms_admin_guard`).
> 반드시 step 0 의 `wsc2026-admin` 신원(`$env:AWS_PROFILE = "wsc2026"`)으로 실행한다.

### 2) [일반 CloudShell] 컨테이너 이미지 빌드 & ECR push (v1.0.0 단일 태그)

> **latest 태그 금지** — mark 3-1 이 이미지 태그 목록 `v1.0.0` 단독 출력을 요구한다.
> 콘솔에서 **일반 CloudShell**(VPC environment 아님 — Docker·업로드 UI 지원, 홈 1GB 영속)을 열고,
> **Actions → Upload file** 로 `app/` 의 `Dockerfile` 과 `book` 두 파일을 올린다 (step 0 에서 복사됨).

```bash
aws configure   # step 0 의 wsc2026-admin 키, region = ap-northeast-2 — 기본 신원(root)로는 ECR CMK 사용 불가
mkdir -p ~/book-image && mv ~/Dockerfile ~/book ~/book-image/ && cd ~/book-image

ECR=$(aws ecr describe-repositories --repository-names wsc2026-book-ecr --query 'repositories[0].repositoryUri' --output text)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" .    # CloudShell 은 x86_64 — --platform 불필요, 태그도 v1.0.0 하나만 생성
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

# ${VAR} 렌더 (PowerShell 5.1 호환)
$c = Get-Content cluster.yaml -Raw
[regex]::Matches($c, '\$\{(\w+)\}') | ForEach-Object { $c = $c.Replace($_.Value, (Get-Item "env:$($_.Groups[1].Value)").Value) }
$c | Set-Content cluster.rendered.yaml -Encoding Ascii
Select-String '\$\{' cluster.rendered.yaml     # 출력이 없어야 함 (치환 누락 검사)

eksctl create cluster -f cluster.rendered.yaml   # 약 20분. 생성 중 퍼블릭 엔드포인트 임시 활성 → 완료 시 자동 private 전환
aws eks describe-cluster --name wsc2026-eks-cluster `
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,endpointPrivateAccess]'   # false, true
```

> 생성이 중간에 끊기면 퍼블릭 엔드포인트가 열린 채 남을 수 있다 — 위 확인이 `true` 면:
> `aws eks update-cluster-config --name wsc2026-eks-cluster --resources-vpc-config endpointPublicAccess=false`
>
> addon 버전은 지정하지 않는다 — eksctl 이 클러스터 버전의 default 버전을 설치한다 (작업 규칙 2: EKS Addon 버전 미고정).
> 생성 완료 후 본 PC 에서는 kubectl 이 불가하다(private-only) — 이후 모든 K8s 작업은 step 4 의 VPC CloudShell.

### 4) [VPC CloudShell] 환경 생성 + 셋업 (세션 초기화 시 이 블록 재실행)

> 콘솔 CloudShell → **Actions → Create VPC environment** → VPC `wsc2026-skills-vpc`,
> Subnet `wsc2026-skills-app-sub-a`, SG `mark-sg`. **이 환경이 그대로 채점 환경이다**(채점 유의 11) —
> 작업 내내 채점 경로(mark-sg → EKS API, wsc2026-admin 신원)를 상시 검증하는 셈.
> **VPC environment 홈은 세션 종료 시 삭제된다(비영속)** — 재접속하면 아래 블록을 통째로 재실행한다.

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
# kubelet clusterDomain 확인 (wsc2026.skills.local — cp-extra SG 가 mark-sg → API 443 을 허용)
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

### 9) [VPC CloudShell] 채점 전 정리 + 채점

> mark.sh 는 step 4 에서 `~/wsc2026/` 에 이미 풀려 있다. 세션이 초기화됐으면 step 4 블록을
> 재실행하고, `_transfer` 를 이미 지운 뒤라면 mark.sh 만 레포 원본을 붙여넣는다(`vi ~/wsc2026/mark.sh`).
> 이 CloudShell(mark-sg + wsc2026-admin 신원)이 곧 채점 환경 — 기본 신원(root)로 돌리면
> check_kms 5건·S3 조회·kubectl 이 전부 실패하므로 `aws configure` 상태를 유지한다.

```bash
# S3 릴레이 제거 (static/ 만 남긴다 — mark 6-1)
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
aws s3 rm "s3://$BUCKET/_transfer/" --recursive

# 채점
bash ~/wsc2026/mark.sh
```

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

- **이름 접두어 변경(30% 변동) 대응**: terraform 은 `name_prefix` 변수(기본 `wsc2026`)로 일괄 변경.
  k8s/eksctl 은 `grep -rl wsc2026 eksctl k8s app | xargs sed -i 's/wsc2026/<새접두어>/g'` 로 치환한다
  (라벨 키 `wsc2026/node` 포함 — cluster.yaml 과 manifest 가 함께 바뀌어 일관됨).
  네트워크(`-skills-*`)·클러스터·테이블·ECR·Lambda·버킷 이름은 별도 변수라 tfvars 에서 개별 변경.
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
- **VPC CloudShell 은 비영속**: 홈 디렉토리가 세션 종료 시 삭제되고 업로드 UI 도 없다.
  도구/파일/kubeconfig 는 step 4 셋업 블록 하나로 복구한다(재접속 시 통째로 재실행, 약 1–2분).
- **HTTP 메트릭은 로그 기반**: 앱이 /metrics 를 노출하지 않아 fluent-bit `log_to_metrics` 필터가
  액세스 로그에서 requests/errors counter 와 duration histogram 을 생성한다(`:2021/metrics`).
  배포 후 step 8 에서 **메트릭 실명을 확인**하고 `prometheus-rules.yaml`/`dashboard.json` 의
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
