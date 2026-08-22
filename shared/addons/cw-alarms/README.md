# cw-alarms 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

CloudWatch 메트릭 필터 → 알람 → SNS 통지 한 묶음. 1과제 Observability 옵션("오류 알람·통지",
set-02/03/05/07/09 task-1 후보), task-3 장애 감지 알람, 2과제 Lambda·EC2 알람 모듈에 대응한다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 0개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_cwalarm_sns_topic_name` | `"skills-alarm-topic"` | 알람 통지 SNS 토픽 이름. 과제지 명시 이름과 정확히 일치시킨다 |
| `addon_cwalarm_email` | `""` | 이메일 구독 주소. 빈 문자열이면 구독을 만들지 않는다 (과제지 무요구 시 비워 둔다) |
| `addon_cwalarm_log_group_name` | `""` | 메트릭 필터를 걸 기존 로그 그룹 이름 (ECS awslogs·Container Insights application 등). 빈 문자열이면 로그 알람을 만들지 않는다 |
| `addon_cwalarm_metric_namespace` | `"Skills/CloudComputing/Task1"` | 로그 메트릭 네임스페이스. 채점 스크립트가 읽는 값이면 과제지 그대로 |
| `addon_cwalarm_log_filters` | `{` | 로그 메트릭 필터·알람 묶음. key 는 terraform 식별자, 이름 3종은 과제지 명시값과 정확히 일치. pattern 은 앱 로그 형식에 맞춘다 |
| `addon_cwalarm_metric_alarms` | `{}` | 서비스 메트릭 알람 묶음. README 의 tfvars 예시에서 필요한 항목만 골라 넣는다. dimensions 값(ALB suffix·DB 식별자 등)은 기존 리소스 값 |
| `addon_cwalarm_waf_cloudfront_name` | `""` | CLOUDFRONT scope Web ACL 이름. 빈 문자열이면 us-east-1 알람·토픽을 만들지 않는다 |
| `addon_cwalarm_waf_blocked_threshold` | `100` | WAF BlockedRequests 알람 임계값 (period 당 Sum) |

## KEEP — 건드리지 않는다

- 기존 세트의 리소스·이름·CIDR. 이름이 충돌하면 기존 것을 지우지 말고 **이 KIT 쪽 변수를 리네임**한다.
- 공식 지급물 — `provided/`, `task.md`, `mark.md`, `mark*.sh`.
- `plan` 에 기존 리소스의 replace/delete 가 보이면 apply 하지 말고 멈춘다.

## CHECK — apply 전 계정·리전

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
```

## RUN

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 Kit의 state를 건드리지 않는다.

```powershell
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

복사할 파일과 순서는 아래 본문을 따른다.

## VERIFY / SCORE

- **VERIFY** = 이 README 본문의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 아래 함정은 이 KIT 고유 문제다.

## 파일

- `cw-alarms.tf` — SNS 토픽(+email 구독) · 로그 메트릭 필터+알람(for_each) · 서비스 메트릭 알람(for_each) · WAF CLOUDFRONT BlockedRequests 알람(us-east-1, 선택)
- `variables.tf` — `addon_cwalarm_*` 변수. 이름 3종(필터·메트릭·알람)은 과제지 명시값으로 tfvars 에서 덮어쓴다

## 부착 절차

1. `cw-alarms.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 기존 리소스를 직접 참조하려면 `var.addon_cwalarm_log_group_name` 을 `aws_cloudwatch_log_group.<기존>.name` 으로 바꾼다.

   ```hcl
   addon_cwalarm_sns_topic_name = "skills-alarm-topic"
   addon_cwalarm_email          = ""                    # 과제지가 요구할 때만
   addon_cwalarm_log_group_name = "/ecs/skills-app"     # 기존 로그 그룹
   addon_cwalarm_metric_namespace = "Skills/CloudComputing/Task1"
   addon_cwalarm_log_filters = {
     "4xx" = { filter_name = "skills-4xx-filter", metric_name = "skills-4xx-count", alarm_name = "skills-4xx-alarm", pattern = "%status=4[0-9][0-9]%" }
     "5xx" = { filter_name = "skills-5xx-filter", metric_name = "skills-5xx-count", alarm_name = "skills-5xx-alarm", pattern = "%status=5[0-9][0-9]%" }
   }
   # 서비스 메트릭 알람 — 필요한 것만 남긴다
   addon_cwalarm_metric_alarms = {
     alb_5xx  = { alarm_name = "skills-alb-5xx", namespace = "AWS/ApplicationELB", metric_name = "HTTPCode_Target_5XX_Count", dimensions = { LoadBalancer = "app/skills-alb/0123456789abcdef" }, threshold = 1 }
     alb_rt   = { alarm_name = "skills-alb-latency", namespace = "AWS/ApplicationELB", metric_name = "TargetResponseTime", dimensions = { LoadBalancer = "app/skills-alb/0123456789abcdef" }, statistic = "Average", threshold = 1, comparison_operator = "GreaterThanThreshold" }
     lambda   = { alarm_name = "skills-lambda-errors", namespace = "AWS/Lambda", metric_name = "Errors", dimensions = { FunctionName = "skills-func" }, threshold = 1 }
     rds_cpu  = { alarm_name = "skills-rds-cpu", namespace = "AWS/RDS", metric_name = "CPUUtilization", dimensions = { DBInstanceIdentifier = "skills-db" }, statistic = "Average", threshold = 80, period = 300, evaluation_periods = 2 }
     ecs_cpu  = { alarm_name = "skills-ecs-cpu", namespace = "AWS/ECS", metric_name = "CPUUtilization", dimensions = { ClusterName = "skills-cluster", ServiceName = "skills-service" }, statistic = "Average", threshold = 80, period = 300 }
     eks_cpu  = { alarm_name = "skills-eks-node-cpu", namespace = "ContainerInsights", metric_name = "node_cpu_utilization", dimensions = { ClusterName = "skills-eks" }, statistic = "Average", threshold = 80, period = 300 }
     waf_reg  = { alarm_name = "skills-waf-blocked", namespace = "AWS/WAFV2", metric_name = "BlockedRequests", dimensions = { WebACL = "skills-waf", Region = "ap-northeast-2", Rule = "ALL" }, threshold = 100, period = 300 }
   }
   # CLOUDFRONT scope WAF 만 (us-east-1)
   addon_cwalarm_waf_cloudfront_name = ""
   ```

   ALB `LoadBalancer` dimension 값은 ARN 의 `app/...` 이하(`aws_lb.<기존>.arn_suffix`)다.
3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws cloudwatch describe-alarms --alarm-name-prefix skills- --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
   aws logs describe-metric-filters --log-group-name /ecs/skills-app
   aws sns list-subscriptions-by-topic --topic-arn <토픽ARN>   # email 은 Confirmed 확인
   ```

## 블록

기존 알람에 통지만 붙이는 경우 새 파일 대신:

```hcl
# aws_cloudwatch_metric_alarm 리소스 안에:
alarm_actions = [aws_sns_topic.addon_alarm.arn]
ok_actions    = [aws_sns_topic.addon_alarm.arn]
```

## TROUBLESHOOT — 이 KIT 고유 함정
- 전부 신규 리소스 — 기존 리소스 재생성 없음. 알람 `alarm_name`·필터 `name`·SNS `name` 변경은 ⚠ 재생성(이름이 식별자)이나 채점 영향 없음.
- **ALARM 상태 확인은 실제 오류를 내야 한다**: 4xx 는 없는 경로 GET 한 번, 5xx 는 앱이 내 주는 경로가 있는지 과제지 확인. 메트릭 반영까지 1~3분(채점 대기 항목당 최대 3분 — set-08 task-1 mark).
- `treat_missing_data = notBreaching` 이라 평시 OK. 채점 스크립트가 `INSUFFICIENT_DATA` 가 아닌 `OK` 를 요구하는 경우에 맞춘 값이다.
- 필터 `pattern` 은 앱 로그 형식에 종속. 기본값은 set-08 앱(`... status=404 ...`) 실측. JSON 로그면 `{ $.status >= 400 && $.status < 500 }` 으로 바꾼다. `aws logs test-metric-filter --filter-pattern '<패턴>' --log-event-messages '<실제 로그 한 줄>'` 로 매칭 확인.
- 로그 그룹이 Terraform 밖(eksctl·Fluent Bit auto_create)에서 만들어지면 apply 순서상 필터가 먼저 실패한다 — 로그 그룹이 생긴 뒤 apply.
- WAF CLOUDFRONT 의 BlockedRequests 는 us-east-1 메트릭이고 알람 액션 SNS 도 같은 리전이어야 한다 — 스니펫이 `-use1` 토픽을 따로 만든다. provider alias `use1` 필요 — 없으면 `versions.tf` 에 추가(waf/README 의 블록).
- email 구독은 수신자가 확인 링크를 눌러야 `Confirmed` — `PendingConfirmation` 상태로는 통지가 안 간다.
- Lambda `Errors` 는 함수 실행이 한 번도 없으면 메트릭 자체가 없다. 알람 존재만 채점하면 무관.

## 실전 구현 (참고용)

- set-08 task-1 `terraform/cloudwatch.tf` — 4xx/5xx 메트릭 필터 + 알람 (액션 없음, 채점 9-x)
- set-08 task-2 module-3-event-handling `terraform/sns.tf` — SNS 토픽
