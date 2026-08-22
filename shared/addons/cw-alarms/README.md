# CloudWatch 알람 부착 KIT

메트릭 필터 → 알람 → SNS 통지 한 묶음.

## 이 KIT이 맞나

- 과제지에 **"오류 알람"·"임계값 초과 시 통지"·"SNS"** → 맞다.
- **대시보드** → [cw-dashboard](../cw-dashboard/README.md) · **로그 쿼리** → [cw-logs-insights](../cw-logs-insights/README.md).
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 알람 재료

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 앱 로그 그룹 | `aws_cloudwatch_log_group.pod_logs` | `.book_app` | `.book_app` |
| Lambda 로그 그룹 | `.book_lambda` | `.book_function` | `.get_booking` |
| 앱 ALB | `aws_lb.book` | **없음** (LBC Ingress) | `aws_lb.app` |
| Lambda 함수 | `aws_lambda_function.book` | `.book_get` | `.get_booking` |
| WAF Web ACL | 없음 | `wsc2026` (CLOUDFRONT) | `unicorn` (CLOUDFRONT) |
| 기존 알람 | **없음** | **없음** | **없음** |
| 기존 SNS 토픽 | **없음** | **없음** | **없음** |

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `cw-alarms.tf` | `set-XX/task-1/terraform/` | SNS 토픽(+email 구독) · 로그 메트릭 필터+알람(for_each) · 서비스 메트릭 알람(for_each) · WAF CLOUDFRONT 알람(us-east-1, 선택) |
| `variables.tf` | `variables-cwalarm-addon.tf` | `addon_cwalarm_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_cwalarm_sns_topic_name` | `"skills-alarm-topic"` | SNS 토픽 이름. 과제지 명시 이름과 정확히 일치 |
| `addon_cwalarm_email` | `""` | 이메일 구독. 빈 문자열이면 구독 안 만든다 |
| `addon_cwalarm_log_group_name` | `""` | 메트릭 필터를 걸 로그 그룹. 빈 문자열이면 로그 알람 안 만든다 |
| `addon_cwalarm_metric_namespace` | `"Skills/CloudComputing/Task1"` | 로그 메트릭 네임스페이스 |
| `addon_cwalarm_log_filters` | map | 필터·메트릭·알람 **이름 3종은 과제지 명시값과 정확히 일치** |
| `addon_cwalarm_metric_alarms` | `{}` | 서비스 메트릭 알람. dimensions 값은 기존 리소스에서 뽑는다 |
| `addon_cwalarm_waf_cloudfront_name` | `""` | CLOUDFRONT scope Web ACL 이름. 빈 문자열이면 us-east-1 알람·토픽 안 만든다 |
| `addon_cwalarm_waf_blocked_threshold` | `100` | WAF BlockedRequests 임계 (period 당 Sum) |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## 0. SNS 토픽

```hcl
# 파일: set-XX/task-1/terraform/cw-alarms.tf   (KIT에서 복사됨)
resource "aws_sns_topic" "addon_alarm" {
  name = var.addon_cwalarm_sns_topic_name
}
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "alarm_topic_arn" { value = aws_sns_topic.addon_alarm.arn }
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 SNS 토픽이 **없다** — 새로 만든다.

```powershell
terraform output -raw alarm_topic_arn
aws sns list-subscriptions-by-topic --topic-arn (terraform output -raw alarm_topic_arn) `
  --query "Subscriptions[].[Protocol,Endpoint,SubscriptionArn]" --output table
```

email 구독은 수신자가 확인 링크를 눌러야 `Confirmed` 다. `PendingConfirmation` 상태면 통지가 안 간다 — 대회 계정 메일함이 없으면 `addon_cwalarm_email = ""` 로 둔다.
</details>

## 1. 로그 메트릭 필터 + 알람

```hcl
# 파일: set-XX/task-1/terraform/cw-alarms.tf   (KIT에서 복사됨)
resource "aws_cloudwatch_log_metric_filter" "addon" {
  for_each       = var.addon_cwalarm_log_filters
  name           = each.value.filter_name
  log_group_name = var.addon_cwalarm_log_group_name   # ← aws_cloudwatch_log_group.<기존>.name 직접 참조 권장
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric_name
    namespace = var.addon_cwalarm_metric_namespace
    value     = "1"
  }
}
```

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_cwalarm_metric_namespace = "Skills/CloudComputing/Task1"
addon_cwalarm_log_filters = {
  "4xx" = { filter_name = "skills-4xx-filter", metric_name = "skills-4xx-count", alarm_name = "skills-4xx-alarm", pattern = "%status=4[0-9][0-9]%" }
  "5xx" = { filter_name = "skills-5xx-filter", metric_name = "skills-5xx-count", alarm_name = "skills-5xx-alarm", pattern = "%status=5[0-9][0-9]%" }
}
```

<details><summary><b>값 뽑기 — 세트별 (로그 그룹 이름 + 패턴 검증)</b></summary>

| 세트 | 로그 그룹 리소스 | output |
| --- | --- | --- |
| set-02 | `aws_cloudwatch_log_group.pod_logs` | **없음** — 아래 블록 추가 |
| set-03 | `aws_cloudwatch_log_group.book_app` | `app_log_group` (있음) |
| set-07 | `aws_cloudwatch_log_group.book_app` | **없음** — 아래 블록 추가 |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_log_group" { value = aws_cloudwatch_log_group.pod_logs.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_log_group" { value = aws_cloudwatch_log_group.book_app.name }
```

```powershell
$lg = terraform output -raw app_log_group

# 실제 로그 한 줄을 먼저 본다 — 패턴은 앱 로그 형식에 종속이다
aws logs tail $lg --since 10m | Select-Object -First 3

# 패턴이 그 줄에 매칭되는지 확인 (여기서 걸러야 알람이 죽지 않는다)
aws logs test-metric-filter --filter-pattern '%status=4[0-9][0-9]%' `
  --log-event-messages '<위에서 복사한 실제 로그 한 줄>'

aws logs describe-metric-filters --log-group-name $lg `
  --query "metricFilters[].[filterName,metricTransformations[0].metricName]" --output table
```

JSON 로그면 패턴을 `{ $.status >= 400 && $.status < 500 }` 로 바꾼다.

로그 그룹이 Terraform 밖(eksctl·Fluent Bit auto_create)에서 만들어지는 경우 필터 apply가 먼저 실패한다 — **로그 그룹이 생긴 뒤 apply한다.**
</details>

## 2. 서비스 메트릭 알람

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_cwalarm_metric_alarms = {
  alb_5xx = { alarm_name = "skills-alb-5xx", namespace = "AWS/ApplicationELB", metric_name = "HTTPCode_Target_5XX_Count", dimensions = { LoadBalancer = "app/skills-alb/0123456789abcdef" }, threshold = 1 }
  lambda  = { alarm_name = "skills-lambda-errors", namespace = "AWS/Lambda", metric_name = "Errors", dimensions = { FunctionName = "skills-func" }, threshold = 1 }
  eks_cpu = { alarm_name = "skills-eks-node-cpu", namespace = "ContainerInsights", metric_name = "node_cpu_utilization", dimensions = { ClusterName = "skills-eks" }, statistic = "Average", threshold = 80, period = 300 }
}
```

<details><summary><b>값 뽑기 — 세트별 (dimensions 값이 전부 output에서 나온다)</b></summary>

**ALB `LoadBalancer` dimension은 ARN 전체가 아니라 `app/...` 이하** = `aws_lb.<기존>.arn_suffix` 다.

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_alb_arn_suffix" { value = aws_lb.book.arn_suffix }
output "app_tg_arn_suffix"  { value = aws_lb_target_group.book.arn_suffix }
output "lambda_function_name" { value = aws_lambda_function.book.function_name }
output "cluster_name"       { value = var.cluster_name }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_alb_arn_suffix" { value = aws_lb.app.arn_suffix }
output "app_tg_arn_suffix"  { value = aws_lb_target_group.app.arn_suffix }
output "lambda_function_name" { value = aws_lambda_function.get_booking.function_name }
```

```powershell
terraform output -raw app_alb_arn_suffix      # → app/wskorea26-alb/0123456789abcdef
terraform output -raw lambda_function_name

# set-03 은 Terraform ALB 가 없다 — LBC 가 만든 ALB 의 suffix 를 CLI 로
aws elbv2 describe-load-balancers `
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].LoadBalancerArn" --output text
# ARN 에서 'app/' 부터 끝까지가 dimension 값이다

# 알람 상태
aws cloudwatch describe-alarms --alarm-name-prefix skills- `
  --query "MetricAlarms[].[AlarmName,StateValue]" --output table
```

| 세트 | 쓸 만한 알람 | 비고 |
| --- | --- | --- |
| set-02 | ALB 5xx · Lambda Errors · ContainerInsights node CPU | `aws_lb.book` / `aws_lb.grafana` 둘 다 있다 |
| set-03 | Lambda Errors · ContainerInsights | ALB는 LBC 생성이라 suffix를 CLI로 |
| set-07 | ALB 5xx · Lambda Errors · ContainerInsights | 앱 ALB는 internal |

Lambda `Errors` 는 함수 실행이 한 번도 없으면 메트릭 자체가 없다. 알람 존재만 채점하면 무관하다.
</details>

## 3. WAF CLOUDFRONT BlockedRequests (us-east-1)

```hcl
# 파일: set-XX/task-1/terraform/cw-alarms.tf   (KIT에서 복사됨)
resource "aws_sns_topic" "addon_alarm_use1" {
  provider = aws.use1
  count    = var.addon_cwalarm_waf_cloudfront_name == "" ? 0 : 1
  name     = "${var.addon_cwalarm_sns_topic_name}-use1"
}

resource "aws_cloudwatch_metric_alarm" "addon_waf_blocked" {
  provider            = aws.use1
  count               = var.addon_cwalarm_waf_cloudfront_name == "" ? 0 : 1
  alarm_name          = "${var.addon_cwalarm_waf_cloudfront_name}-blocked"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  dimensions          = { WebACL = var.addon_cwalarm_waf_cloudfront_name, Region = "CloudFront", Rule = "ALL" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.addon_cwalarm_waf_blocked_threshold
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.addon_alarm_use1[0].arn]
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | Web ACL 이름 | `use1` alias |
| --- | --- | --- |
| set-02 | 없음 → `""` 로 꺼 둔다 | 없음 |
| set-03 | `${var.name_prefix}-waf` | **이미 있음** (`providers.tf`) |
| set-07 | `unicorn-waf` | **이미 있음** (`versions.tf`) |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "waf_name" { value = aws_wafv2_web_acl.wsc2026.name }   # set-07 은 .unicorn
```

```powershell
terraform output -raw waf_name
# → terraform.tfvars 의 addon_cwalarm_waf_cloudfront_name 에 넣는다

# CLOUDFRONT WAF 메트릭은 us-east-1, dimension Region 값은 "CloudFront"
aws cloudwatch list-metrics --namespace AWS/WAFV2 --region us-east-1 `
  --query "Metrics[?MetricName=='BlockedRequests'].Dimensions" --output json
aws cloudwatch describe-alarms --region us-east-1 --alarm-name-prefix (terraform output -raw waf_name) `
  --query "MetricAlarms[].[AlarmName,StateValue]" --output table
```

**알람 액션 SNS도 같은 리전(us-east-1)이어야 한다** — KIT이 `-use1` 토픽을 따로 만든다.
</details>

## 4. 기존 알람에 통지만 붙이기

```hcl
# 파일: set-XX/task-1/terraform/cloudwatch.tf
# 기존 aws_cloudwatch_metric_alarm 리소스 블록 *안에*
alarm_actions = [aws_sns_topic.addon_alarm.arn]
ok_actions    = [aws_sns_topic.addon_alarm.arn]
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 기존 알람이 **없다** — 이 블록은 당일 알람을 먼저 만든 뒤에나 쓴다.

```powershell
terraform output -raw alarm_topic_arn
aws cloudwatch describe-alarms --query "MetricAlarms[].[AlarmName,AlarmActions]" --output table

# 통지 테스트 (SNS 로 직접)
aws sns publish --topic-arn (terraform output -raw alarm_topic_arn) --message "test"
```
</details>

## VERIFY

```powershell
aws cloudwatch describe-alarms --alarm-name-prefix skills- `
  --query "MetricAlarms[].[AlarmName,StateValue,StateReason]" --output table
aws logs describe-metric-filters --log-group-name (terraform output -raw app_log_group)
aws sns list-subscriptions-by-topic --topic-arn (terraform output -raw alarm_topic_arn)
```

## TROUBLESHOOT

- **ALARM 상태 확인은 실제 오류를 내야 한다.** 4xx는 없는 경로 GET 한 번, 5xx는 앱이 내주는 경로가 있는지 과제지 확인. 메트릭 반영까지 1~3분(채점 대기 항목은 항목당 최대 3분).
- `treat_missing_data = notBreaching` 이라 평시 `OK` 다. 채점이 `INSUFFICIENT_DATA` 가 아닌 `OK` 를 요구하는 경우에 맞춘 값이다.
- 필터 `pattern` 은 앱 로그 형식에 종속이다. `aws logs test-metric-filter` 로 반드시 먼저 검증한다.
- 로그 그룹이 Terraform 밖에서 만들어지면 필터 apply가 먼저 실패한다.
- WAF CLOUDFRONT BlockedRequests는 **us-east-1 메트릭**이고 SNS도 같은 리전이어야 한다. dimension `Region` 값은 리전 이름이 아니라 문자열 `"CloudFront"` 다.
- email 구독은 `Confirmed` 여야 통지가 간다.
- 알람 `alarm_name`·필터 `name`·SNS `name` 변경은 재생성이지만(이름이 식별자) 채점 영향은 없다.

## 실전 구현 (참고용)

- set-08 task-1 `terraform/cloudwatch.tf` — 4xx/5xx 메트릭 필터 + 알람 (액션 없음)
- set-08 task-2 module-3-event-handling `terraform/sns.tf` — SNS 토픽

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
