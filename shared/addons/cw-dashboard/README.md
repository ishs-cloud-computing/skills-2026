# CloudWatch 대시보드 부착 KIT

대시보드 한 장 — ALB · EKS(Container Insights) · Lambda · WAF 위젯을 변수로 골라 넣는다. dimension 변수가 빈 위젯은 자동으로 빠진다.

## 이 KIT이 맞나

- 과제지에 **"대시보드"·"모니터링 환경 구성"** → 맞다.
- **Grafana 대시보드** 요구 → [grafana-panels](../grafana-panels/README.md) (set-03/07 `k8s/monitoring/dashboard.json` 과 무관하지 않다).
- **경보** → [cw-alarms](../cw-alarms/README.md).
- 대시보드 본문 변경은 in-place다.

## 세트별 위젯 재료

| dimension | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| ALB `arn_suffix` | `aws_lb.book.arn_suffix` | **없음** (LBC 생성 — CLI로) | `aws_lb.app.arn_suffix` |
| Lambda 함수 | `aws_lambda_function.book` | `.book_get` | `.get_booking` |
| EKS 클러스터 | `wskorea26-cluster` | `wsc2026-eks-cluster` | `unicorn-eks-cluster` |
| WAF Web ACL | **없음** | `${var.name_prefix}-waf` (CLOUDFRONT) | `unicorn-waf` (CLOUDFRONT) |
| RDS · ECS | **없음** | **없음** | **없음** |
| 기존 대시보드 | **없음** | **없음** | **없음** |

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `cw-dashboard.tf` | `set-XX/task-1/terraform/` | `aws_cloudwatch_dashboard` 1개. `templatefile` 로 JSON 렌더 |
| `dashboard.json.tftpl` | **`.tf` 와 같은 디렉터리** (`path.module` 기준) | 위젯 JSON |
| `variables.tf` | `variables-cwdash-addon.tf` | `addon_cwdash_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_cwdash_name` | `"skills-dashboard"` | 대시보드 이름. 과제지 명시 이름과 정확히 일치 |
| `addon_cwdash_region` | `"ap-northeast-2"` | 위젯이 읽는 메트릭 리전 (대시보드 자체는 리전 무관) |
| `addon_cwdash_period` | `60` | 위젯 공통 집계 주기(초) |
| `addon_cwdash_alb_arn_suffix` | `""` | **`app/<이름>/<id>`** — ARN 전체가 아니다 |
| `addon_cwdash_rds_instance_id` | `""` | task-1에는 RDS가 없다 |
| `addon_cwdash_ecs_cluster_name` / `_service_name` | `""` | task-1에는 ECS가 없다 |
| `addon_cwdash_eks_cluster_name` | `""` | ContainerInsights ClusterName (addon 필요) |
| `addon_cwdash_lambda_function_name` | `""` | Lambda FunctionName |
| `addon_cwdash_waf_acl_name` | `""` | Web ACL 이름 |
| `addon_cwdash_waf_metric_region` | `"us-east-1"` | CLOUDFRONT는 us-east-1, REGIONAL은 ALB 리전 |
| `addon_cwdash_waf_dimension_region` | `"Global"` | CLOUDFRONT는 `Global`, REGIONAL은 `ap-northeast-2` |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## FAST — terraform 없이 CLI 로 붙이기

대시보드는 본문이 통째로 JSON 한 덩어리다. terraform 을 거칠 이유가 거의 없다.

**대가**: terraform state 와 실물이 어긋난다. 이 세트에 이후 `apply` 를 걸면 되돌아가므로,
CLI 로 붙였으면 그 세트는 더 apply 하지 않거나 나중에 같은 값을 `.tf` 에도 넣는다.

```powershell
# 콘솔에서 위젯을 눈으로 맞춘 뒤 그 JSON 을 그대로 가져오는 게 제일 빠르다
aws cloudwatch get-dashboard --dashboard-name <이름> --query DashboardBody --output text `
  | Set-Content -Encoding utf8 dashboard.json

# 수정 후 다시 올린다 (put-dashboard 는 전체 교체다)
aws cloudwatch put-dashboard --dashboard-name <이름> --dashboard-body file://dashboard.json

# 확인 — 유효하지 않은 위젯은 여기서 걸린다
aws cloudwatch list-dashboards --query 'DashboardEntries[].DashboardName'
```

- `put-dashboard` 는 **전체 교체**다. 위젯 하나를 더할 때도 기존 JSON 을 받아서 `widgets` 배열에 추가한 뒤 통째로 올린다.
- 위젯 JSON 이 잘못돼도 `put-dashboard` 는 성공하고 **응답의 `DashboardValidationMessages`** 에만 적힌다. 응답을 눈으로 본다.
- dimension 값은 추측하지 말고 먼저 조회한다: `aws cloudwatch list-metrics --namespace <ns> --metric-name <지표> --query 'Metrics[].Dimensions'`

## 1. 대시보드 리소스

```hcl
# 파일: set-XX/task-1/terraform/cw-dashboard.tf   (KIT에서 복사됨)
resource "aws_cloudwatch_dashboard" "addon" {
  dashboard_name = var.addon_cwdash_name
  dashboard_body = templatefile("${path.module}/dashboard.json.tftpl", {
    region                = var.addon_cwdash_region
    period                = var.addon_cwdash_period
    alb_arn_suffix        = var.addon_cwdash_alb_arn_suffix
    eks_cluster_name      = var.addon_cwdash_eks_cluster_name
    lambda_function_name  = var.addon_cwdash_lambda_function_name
    waf_acl_name          = var.addon_cwdash_waf_acl_name
    waf_metric_region     = var.addon_cwdash_waf_metric_region
    waf_dimension_region  = var.addon_cwdash_waf_dimension_region
  })
}
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "dashboard_name" { value = aws_cloudwatch_dashboard.addon.dashboard_name }
output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.addon.dashboard_name}"
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 CloudWatch 대시보드가 **없다** — 새로 만든다.

```powershell
terraform output -raw dashboard_name
terraform output -raw dashboard_url      # 브라우저로 열어 위젯에 데이터가 그려지는지 본다

aws cloudwatch get-dashboard --dashboard-name (terraform output -raw dashboard_name) `
  --query DashboardBody --output text | ConvertFrom-Json |
  Select-Object -ExpandProperty widgets |
  Select-Object type, @{n='title';e={$_.properties.title}}
```

위젯이 비어 보이면 dimension 오타다 — 아래 2번으로 실제 값과 대조한다.
</details>

## 2. dimension 값 채우기

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_cwdash_name                 = "skills-dashboard"
addon_cwdash_region               = "ap-northeast-2"
addon_cwdash_alb_arn_suffix       = "app/wskorea26-alb/0123456789abcdef"
addon_cwdash_eks_cluster_name     = "wskorea26-cluster"
addon_cwdash_lambda_function_name = "wskorea26-book-func"
addon_cwdash_waf_acl_name         = ""
addon_cwdash_waf_metric_region    = "us-east-1"
addon_cwdash_waf_dimension_region = "Global"
```

<details><summary><b>값 뽑기 — 세트별 (전부 output에서 나온다)</b></summary>

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_alb_arn_suffix"   { value = aws_lb.book.arn_suffix }
output "lambda_function_name" { value = aws_lambda_function.book.function_name }
output "cluster_name"         { value = var.cluster_name }

# 파일: set-03/task-1/terraform/outputs.tf
output "lambda_function_name" { value = aws_lambda_function.book_get.function_name }
output "waf_name"             { value = aws_wafv2_web_acl.wsc2026.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_alb_arn_suffix"   { value = aws_lb.app.arn_suffix }
output "lambda_function_name" { value = aws_lambda_function.get_booking.function_name }
output "waf_name"             { value = aws_wafv2_web_acl.unicorn.name }
```

```powershell
terraform output -raw app_alb_arn_suffix      # → app/<이름>/<id>  ← 이 형태여야 한다
terraform output -raw lambda_function_name
terraform output -raw waf_name
(terraform output -raw cluster_arn).Split('/')[-1]    # set-03/set-07 은 cluster_arn 이 있다

# set-03 — LBC 가 만든 ALB 의 suffix (ARN 에서 'app/' 이하)
$arn = aws elbv2 describe-load-balancers `
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].LoadBalancerArn" --output text
$arn.Substring($arn.IndexOf('app/'))

# 실제로 존재하는 dimension 인지 대조 (여기 안 나오면 위젯이 빈다)
aws cloudwatch list-metrics --namespace AWS/ApplicationELB `
  --query "Metrics[0:3].Dimensions" --output json
aws cloudwatch list-metrics --namespace ContainerInsights `
  --query "Metrics[0:3].Dimensions" --output json
```

| 세트 | WAF 위젯 | `waf_dimension_region` |
| --- | --- | --- |
| set-02 | 없음 → `addon_cwdash_waf_acl_name = ""` | — |
| set-03 | CLOUDFRONT | `"Global"`, metric region `us-east-1` |
| set-07 | CLOUDFRONT | `"Global"`, metric region `us-east-1` |

`ContainerInsights` 네임스페이스는 `amazon-cloudwatch-observability` addon이 켜져야 생긴다 → [observability](../observability/README.md) 경로 A. 안 켜도 apply는 성공하고 위젯만 빈다.
</details>

## 3. 위젯 하나 추가

```json
// 파일: set-XX/task-1/terraform/dashboard.json.tftpl
// 템플릿 안 `]` 앞에, 바로 앞 위젯 뒤에 `,` 로 이어서
{
  "type": "metric", "width": 12, "height": 6,
  "properties": {
    "title": "<제목>", "region": "${region}", "view": "timeSeries", "stat": "Sum", "period": ${period},
    "metrics": [["<Namespace>", "<MetricName>", "<DimName>", "<DimValue>"]]
  }
}
```

<details><summary><b>값 뽑기 — 세트별 (자주 쓰는 메트릭 조합)</b></summary>

| 위젯 | Namespace / MetricName | dimension |
| --- | --- | --- |
| ALB 5xx | `AWS/ApplicationELB` / `HTTPCode_Target_5XX_Count` | `LoadBalancer` = `app/<이름>/<id>` |
| ALB 지연 | `AWS/ApplicationELB` / `TargetResponseTime` | 동일 |
| Lambda 오류 | `AWS/Lambda` / `Errors` | `FunctionName` |
| EKS 노드 CPU | `ContainerInsights` / `node_cpu_utilization` | `ClusterName` |
| WAF 차단 | `AWS/WAFV2` / `BlockedRequests` | `WebACL`, `Region`, `Rule=ALL` |
| CloudFront 요청 | `AWS/CloudFront` / `Requests` | `DistributionId`, `Region=Global` (us-east-1 메트릭) |

```powershell
# CloudFront 위젯을 넣을 때
terraform output -raw cloudfront_id

# 값이 실제로 있는지
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Errors `
  --dimensions Name=FunctionName,Value=(terraform output -raw lambda_function_name) `
  --start-time (Get-Date).AddHours(-1).ToUniversalTime().ToString("s") `
  --end-time (Get-Date).ToUniversalTime().ToString("s") --period 300 --statistics Sum
```
</details>

<details><summary><b>Terraform 없이 CLI로 넣기 (콘솔에서 JSON 편집한 뒤)</b></summary>

```powershell
aws cloudwatch put-dashboard --dashboard-name skills-dashboard --dashboard-body file://dashboard.json

# 되돌리기 — 현재 본문을 파일로 내려둔다
aws cloudwatch get-dashboard --dashboard-name skills-dashboard --query DashboardBody --output text > dashboard.json
```

`dashboard.json.tftpl` 을 손으로 렌더하려면 `${...}` 자리를 값으로 채우고 `%{ if }`·`%{ endif }` 줄을 지운다.
</details>

## VERIFY

```powershell
$d = terraform output -raw dashboard_name
aws cloudwatch get-dashboard --dashboard-name $d --query DashboardBody --output text |
  ConvertFrom-Json | Select-Object -ExpandProperty widgets |
  Select-Object type, @{n='title';e={$_.properties.title}}
terraform output -raw dashboard_url
```

콘솔 CloudWatch → Dashboards에서 위젯에 데이터가 그려지는지 본다. **메트릭 없음 = dimension 오타**다.

## TROUBLESHOOT

- 대시보드 본문 변경은 in-place. `dashboard_name` 변경은 재생성이지만 채점 영향은 없다.
- 위젯 `x`·`y` 를 일부러 뺐다 — 넣으면 전 위젯에 넣어야 하고, 빈 위젯이 빠질 때 좌표가 겹친다.
- **ALB `LoadBalancer` dimension은 ARN이 아니라 `app/<이름>/<id>`** (`arn_suffix`).
- WAF CLOUDFRONT scope는 메트릭 리전 `us-east-1` + dimension `Region=Global`. 대시보드 리소스 자체는 리전 무관이라 provider alias가 필요 없다.
- `ContainerInsights` 네임스페이스는 addon이 켜져야 생긴다. 안 켜면 위젯이 빌 뿐 apply는 성공한다.
- `templatefile` 은 `.tftpl` 안에서 `$${`·`%%{` 로 이스케이프해야 리터럴 `${` 를 쓸 수 있다.
- 채점이 위젯 개수·제목을 읽을 수 있다 — 과제지가 지정한 메트릭이 있으면 **위젯 제목을 그 문구로** 맞춘다.

## 실전 구현 (참고용)

없음 — 저장소 task-1 세트에 `aws_cloudwatch_dashboard` 는 없다. Grafana 대시보드는 set-02/03/07 task-1 `k8s/monitoring/dashboard.json` 이며 CloudWatch 대시보드와 별개다.

---

## 막히면 여는 순서

인자 이름이나 조합에서 막히면 ① 위 **실전 구현**(이미 apply 가 통과한 코드) → ② 로컬 스키마 명령 → ③ 공식 문서 순으로 연다. 대회장 인터넷은 공식 문서까지 열려 있다. 그래도 ①②를 먼저 여는 건 브라우저보다 빠르고, 블로그에서 인자 이름을 베껴 프로바이더·차트 버전이 어긋나는 일이 없어서다.

```powershell
terraform providers schema -json | jq '.provider_schemas[].resource_schemas["<리소스타입>"].block.attributes | keys'
aws <서비스> <명령> help
kubectl explain <리소스>.spec --recursive
```

리소스별 공식 문서 주소·이 저장소의 구현 위치·흔히 막히는 인자는 [DOC-LINKS 4절 리소스별 색인](../../../DOC-LINKS.md#4-리소스별-색인)에 한 줄씩 있다. 리소스 타입(`aws_s3_bucket` 등)으로 Ctrl+F 한다.

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), 세트별 리소스 주소는 [대조표](../../../KIT-INDEX.md#세트별-리소스-주소-대조표-task-1)(표에 없는 세트는 [주소 찾는 명령](../../../KIT-INDEX.md#표에-없는-세트는-직접-찾는다)), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
