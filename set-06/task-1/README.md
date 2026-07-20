# set-06 / task-1 — 런북 (PowerShell)

EKS(Bottlerocket) 위 Book API + CloudFront 단일 엔드포인트(S3 정적 · ALB API · Lambda 조회 · Grafana).
**NAT 없음 / Private Subnet 2개.** 설계 근거·함정은 [plan.md](plan.md), Linux/bash 런북은 [README.linux.md](README.linux.md) 참고.

> 문서 사이트: <https://skills-2026-docs.netlify.app>

## 디렉토리

```
task-1/
├── terraform/        # AWS 리소스 (WAF 만 us-east-1, 나머지 ap-northeast-2)
│   └── lambda/       # 조회 API + EMF 메트릭
├── eksctl/           # 클러스터 + Bottlerocket 노드그룹 2개
│   └── bootstrap/    # 노드명 변경 스크립트 (bootstrap container user-data)
├── k8s/              # apply 순서: 00-namespace → app/ → monitoring/ → logging/
├── app/Dockerfile    # scratch + 제공 바이너리 (zstd push)
└── plan.md           # 설계 문서 (요구사항↔채점 매핑, 함정 26개)
```

## 사전 정의 — 템플릿 치환 함수 (envsubst 대체)

`${VAR}` 플레이스홀더를 환경 변수로 치환한다. **세션 시작 시 한 번 실행.**

```powershell
function Expand-Tpl($Path) {
  [regex]::Replace((Get-Content -Raw $Path), '\$\{(\w+)\}',
    { param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value) })
}
```

## 0. 사전 준비

```powershell
cd set-06\task-1\terraform
$env:AWS_REGION = "ap-northeast-2"
$env:NUM = "01"              # 비번호로 교체
```

## 1. ECR 먼저 (이미지 push 가 EKS 보다 선행)

```powershell
terraform init
terraform apply -var "bibunho=$env:NUM" -target="aws_ecr_repository.book" -target="aws_ecr_repository.direct" -target="aws_ecr_pull_through_cache_rule.public"

$env:ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$env:ECR = "$env:ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com"
```

> **병렬 실행 가능**: 1단계 완료 후 2·3·4단계는 서로 독립(터미널 3개에서 동시 실행 가능, 대기시간 단축).
> 단 5단계(EKS 생성)는 3단계(테라폼 출력값)와 4단계(bootstrap 이미지 push) 둘 다 끝나야 시작 가능.

## 2. book 이미지 빌드·push (zstd — 채점 2-2 의 3MB 제한)

```powershell
aws ecr get-login-password | docker login --username AWS --password-stdin $env:ECR

# oci-mediatypes / force-compression / 단일 아키텍처 전부 필수 (plan.md §3.3)
docker buildx build --platform linux/amd64 --provenance=false `
  --output "type=image,name=$env:ECR/book:latest,oci-mediatypes=true,compression=zstd,compression-level=19,force-compression=true,push=true" `
  -f ..\app\Dockerfile ..\..\..\shared\provided\set-06-task-1

# 3145728(3MB) 이하 확인
aws ecr describe-images --repository-name book --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text
```

## 3. 나머지 AWS 리소스 (CloudFront 배포 포함 — 최대 15분)

```powershell
terraform apply -var "bibunho=$env:NUM"
terraform output -json | Out-File outputs.json -Encoding utf8

# outputs.json → 환경 변수 일괄 주입
$out = Get-Content outputs.json -Raw | ConvertFrom-Json
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

# 작업 변수 영구화 (`set-06\task-1\.env.ps1`) — 새 터미널·재부팅 후에도 이어서 작업 가능하게 파일로 박아둔다
@"
`$env:AWS_REGION          = "ap-northeast-2"
`$env:NUM                 = "$env:NUM"
`$env:ACCOUNT_ID          = "$env:ACCOUNT_ID"
`$env:ECR                 = "$env:ECR"
`$env:VPC_ID              = "$env:VPC_ID"
`$env:SUBNET_A_ID         = "$env:SUBNET_A_ID"
`$env:SUBNET_B_ID         = "$env:SUBNET_B_ID"
`$env:EKS_KMS_ARN         = "$env:EKS_KMS_ARN"
`$env:NODE_SHARED_SG_ID   = "$env:NODE_SHARED_SG_ID"
`$env:BOOK_POD_SG_ID      = "$env:BOOK_POD_SG_ID"
`$env:BOOK_TG_ARN         = "$env:BOOK_TG_ARN"
`$env:GRAFANA_TG_ARN      = "$env:GRAFANA_TG_ARN"
`$env:BOOK_APP_POLICY_ARN = "$env:BOOK_APP_POLICY_ARN"
`$env:GRAFANA_POLICY_ARN  = "$env:GRAFANA_POLICY_ARN"
`$env:FLUENTBIT_POLICY_ARN = "$env:FLUENTBIT_POLICY_ARN"
`$env:LBC_POLICY_ARN      = "$env:LBC_POLICY_ARN"
`$env:NODE_PTC_POLICY_ARN = "$env:NODE_PTC_POLICY_ARN"
`$env:CF_DOMAIN           = "$env:CF_DOMAIN"
"@ | Set-Content ..\.env.ps1

. ..\.env.ps1   # 새 터미널로 이어서 할 땐 task-1 에서 `. .\.env.ps1` 만 다시 실행
```

## 4. 보조 이미지 push + PTC 워밍업 (인터넷 있는 로컬에서)

```powershell
# bootstrap container (노드 부팅 경로 — PTC 의존 금지)
docker pull public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.4.0
docker tag public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.4.0 "$env:ECR/gj2026/br-bootstrap:1.0.0"
docker push "$env:ECR/gj2026/br-bootstrap:1.0.0"

# Grafana (Docker Hub 전용 → 미러), LBC
docker pull grafana/grafana:13.1.0
docker tag grafana/grafana:13.1.0 "$env:ECR/mirror/grafana:13.1.0"
docker push "$env:ECR/mirror/grafana:13.1.0"
docker pull public.ecr.aws/eks/aws-load-balancer-controller:v2.17.1
docker tag public.ecr.aws/eks/aws-load-balancer-controller:v2.17.1 "$env:ECR/mirror/aws-load-balancer-controller:v2.17.1"
docker push "$env:ECR/mirror/aws-load-balancer-controller:v2.17.1"

# PTC 캐시 워밍업 (nginx-test 4-5 대비, fluent-bit)
docker pull "$env:ECR/ecr-public/nginx/nginx:latest"
docker pull "$env:ECR/ecr-public/aws-observability/aws-for-fluent-bit:3.4.8"
```

## 5. EKS 클러스터 (약 15~20분 소요)

bootstrap 스크립트를 base64 인코딩할 때 **CRLF 를 반드시 LF 로 정규화**한다
(CRLF 가 남으면 Bottlerocket 에서 스크립트 실행 실패 → 노드 부팅 중단).

```powershell
cd ..\eksctl

function Get-B64Lf($Path) {
  $s = (Get-Content -Raw $Path) -replace "`r", ""
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
}
$env:BOOTSTRAP_USERDATA_ADDON = Get-B64Lf "bootstrap\set-hostname-addon.sh"
$env:BOOTSTRAP_USERDATA_APP   = Get-B64Lf "bootstrap\set-hostname-app.sh"

Expand-Tpl cluster.yaml | Out-File cluster.rendered.yaml -Encoding utf8
eksctl create cluster -f cluster.rendered.yaml

aws eks update-kubeconfig --name gj2026-eks-cluster
kubectl get nodes   # gj2026.i-xxxx.(addon|app).node 4개 — 실패 시 plan.md §3.5.1 fallback
```

## 6. k8s 리소스

```powershell
cd ..\k8s

# Pod SG 활성화 (SGP 전제, 신규 Pod 부터 적용)
kubectl set env daemonset aws-node -n kube-system ENABLE_POD_ENI=true

kubectl apply -f 00-namespace.yaml

# LBC (TargetGroupBinding CRD 제공 — TGB 보다 선행)
helm repo add eks https://aws.github.io/eks-charts
Expand-Tpl lbc-values.yaml | Out-File lbc-values.rendered.yaml -Encoding utf8
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system -f lbc-values.rendered.yaml

# app (${ACCOUNT_ID}/${BOOK_POD_SG_ID}/${BOOK_TG_ARN} 치환 후 apply)
Get-ChildItem app\*.yaml | ForEach-Object { Expand-Tpl $_.FullName | kubectl apply -f - }

# Grafana (release 이름 grafana 고정 — Service 명이 TGB serviceRef 와 일치해야 함)
helm repo add grafana-community https://grafana-community.github.io/helm-charts
Expand-Tpl monitoring\grafana-values.yaml | Out-File monitoring\grafana-values.rendered.yaml -Encoding utf8
helm upgrade --install grafana grafana-community/grafana -n monitoring -f monitoring\grafana-values.rendered.yaml
kubectl apply -f monitoring\dashboard-configmap.yaml
Expand-Tpl monitoring\grafana-tgb.yaml | kubectl apply -f -

# Fluent Bit (release 이름 = DaemonSet 이름 aws-for-fluent-bit — 채점이 rollout restart)
Expand-Tpl logging\fluent-bit-values.yaml | Out-File logging\fluent-bit-values.rendered.yaml -Encoding utf8
helm upgrade --install aws-for-fluent-bit eks/aws-for-fluent-bit -n logging -f logging\fluent-bit-values.rendered.yaml
```

## 7. 검증 (plan.md §7 전체 시드)

PowerShell 의 `curl` 은 Invoke-WebRequest 별칭이므로 **반드시 `curl.exe`** 를 쓴다.

```powershell
$CF = "https://$env:CF_DOMAIN"
curl.exe -s -o NUL -w "%{http_code} %header{x-cache}`n" $CF              # 200 Miss
curl.exe -s -o NUL -w "%{http_code} %header{x-cache}`n" "$CF/index.html" # 200 Hit(2회째)
curl.exe -sX POST -H "Content-Type: application/json" -d '{\"client_id\":\"C001\",\"username\":\"Alice\",\"email\":\"kim@example.com\",\"concert_name\":\"Busan2025\"}' "$CF/v1/book"
curl.exe -s "$CF/reservation?client_id=C001"
curl.exe -s -w " %{http_code}`n" "$CF/v1/book"                        # Method Not Allowed 405
curl.exe -s -w " %{http_code}`n" "$CF/reservation?client_id=123abc"   # Access Denied 403
```

## 8. 채점 전 정리

```powershell
# DynamoDB 아이템 0개 — Deny 정책을 일시 해제해야 삭제 가능 (plan.md §3.4)
cd ..\terraform
terraform apply -var enable_ddb_write_deny=false

$ids = (aws dynamodb scan --table-name books --projection-expression booking_id --query 'Items[].booking_id.S' --output text) -split "\s+"
foreach ($id in $ids) {
  aws dynamodb delete-item --table-name books --key "{\"booking_id\":{\"S\":\"$id\"}}"
}

terraform apply -var enable_ddb_write_deny=true

# CloudFront 캐시 무효화
$distId = (Get-Content outputs.json -Raw | ConvertFrom-Json).cloudfront_distribution_id.value
aws cloudfront create-invalidation --distribution-id $distId --paths '/*'
```

---

## 문제 해결

| 증상 | 원인 | 조치 |
|---|---|---|
| `kubectl get nodes` 가 4개 미만 / 계속 `NotReady` | bootstrap container 스크립트에 CRLF 잔존 → `apiclient set` 실패, 또는 `provider-id` 누락으로 CCM 이 노드↔EC2 매칭 실패 (§3.5.1) | `Get-B64Lf` 로 재인코딩했는지 확인 → 그래도 안 되면 `nodeGroups`(self-managed) 로 전환 |
| 노드 이름이 `gj2026.i-xxxx...` 가 아니라 `i-0abc...` 형태 | `hostname-override-source` 를 쓴 것 (managed nodegroup 기본 경로는 이 포맷만 지원) | bootstrap container 경로(5단계)를 그대로 썼는지 재확인, cluster.rendered.yaml 에 `bootstrap-containers` 블록이 렌더됐는지 확인 |
| nginx-test / fluent-bit Pod 가 `ImagePullBackOff` | PTC(pull-through cache) 캐시 워밍업(4단계) 을 건너뜀 | 4단계의 `docker pull $ECR/ecr-public/...` 두 줄을 재실행 |
| book 또는 grafana TargetGroupBinding 이 계속 `unhealthy` | SGP 의 ALB SG→Pod SG 8080 규칙 누락, 또는 `ENABLE_POD_ENI=true` 를 Pod 생성 **이전에** 안 걸었음 (§3.6.1) | `kubectl set env daemonset aws-node ...` 를 먼저 실행했는지 확인 후 Pod 재생성(rollout restart) |
| Grafana Service 가 안 보이거나 TGB 가 대상 못 찾음 | helm release 이름이 `grafana` 가 아님 — Service 명이 TGB `serviceRef` 와 어긋남 | `helm upgrade --install grafana ...` 처럼 release 이름을 정확히 `grafana` 로 고정 |
| `terraform apply` 가 WAF 리소스에서 리전 오류 | CLOUDFRONT scope Web ACL 은 반드시 `us-east-1` provider 여야 함 (§3.10) | WAF 리소스에 `provider = aws.us_east_1` alias 지정 확인 |
| curl 결과가 이상하거나 `Invoke-WebRequest` 에러가 남 | PowerShell 의 `curl` 은 `Invoke-WebRequest` 별칭 | 7단계처럼 반드시 `curl.exe` 로 호출 |
| DynamoDB `delete-item` 이 `AccessDeniedException` | `enable_ddb_write_deny=true` 상태에서 삭제 시도 (8단계 순서를 건너뜀) | `terraform apply -var enable_ddb_write_deny=false` 먼저 실행 후 삭제 |

각 항목의 근본 원인 분석은 `plan.md` 해당 절 참고.

## 설계 요약 (상세는 plan.md)

- **Lambda 는 ALB 뒤가 아니라 CloudFront 직결** (Function URL + OAC) — task.md 가 TG 를 2개만 명명 (§0-1)
- **WAF 는 CLOUDFRONT scope(us-east-1)** — Web ACL 1개로 `/v1/book`·`/reservation` 모두 커버 (§3.10)
- **DynamoDB 는 Gateway Endpoint 뿐** (Interface 미존재), 1-2 채점 안 깨짐 — jmespath 실측 (§0-2)
- **IRSA 역할은 eksctl 이 생성** (roleName 지정), Terraform 은 정책만 — OIDC 선후관계 해소
- **채점 4-5 는 SecurityGroupPolicy** — Pod SG ingress 를 ALB SG 참조로만 개방 (§3.6.1)
- **노드명 변경은 bootstrap container** — Bottlerocket 에 셸 없음, hostname-override + provider-id (§3.5.1)
- 사전 실측 필수 항목: plan.md §6.1 리스크 순위 / §6.2 미확정 항목
