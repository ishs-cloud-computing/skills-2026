# Step Functions hardening KIT

기존 Step Functions state machine에 **CloudWatch Logs 전달**, X-Ray tracing, 선택적 SNS Publish와 S3 Object Created → EventBridge → `StartExecution` 흐름을 부착하는 COPY KIT이다. 이 디렉터리는 독립 Terraform state나 독립 `apply` 대상이 아니다.

## 포함 파일

| 파일 | 역할 |
| --- | --- |
| `sfn-hardening.tf` | 로그 그룹, 기존 실행 역할 정책, 선택적 S3 EventBridge 규칙·대상 역할 |
| `variables.tf` | 기존 state machine·실행 역할 이름, 로그 보존, SNS·S3 트리거 입력 변수 |

## 부착 절차

대상 모듈의 `task.md`, `mark.md`, `mark*.sh`, `NOTES.md`를 먼저 읽고 기존 state machine과 실행 역할 이름을 확인한다. 두 `.tf` 파일을 대상 Terraform 루트에 **복사**하고, 다른 이름의 기존 리소스와 충돌하면 이 KIT 쪽 리소스명을 조정한다.

```hcl
addon_sfnhard_state_machine_name  = "<기존 state machine 이름>"
addon_sfnhard_role_name           = "<기존 state machine 실행 역할 이름>"
addon_sfnhard_log_retention_days  = 7
addon_sfnhard_sns_topic_arn       = ""       # SNS Publish 요구 때만 ARN 입력
addon_sfnhard_s3_bucket_name      = ""       # S3 Object Created 트리거 요구 때만 입력
addon_sfnhard_s3_key_prefix       = "input/" # 전체 버킷이면 빈 문자열
```

기존 `aws_sfn_state_machine`에 아래 설정을 추가한다. `log_destination`은 이 KIT가 만든 로그 그룹 ARN 뒤에 반드시 `:*`를 붙인다. S3 트리거를 켰다면 **기존** `aws_s3_bucket_notification`의 `eventbridge = true`도 추가한다. notification 리소스를 중복 생성하지 않는다.

```hcl
logging_configuration {
  include_execution_data = true
  level                  = "ALL"
  log_destination        = "${aws_cloudwatch_log_group.addon_sfnhard.arn}:*"
}

tracing_configuration {
  enabled = true
}
```

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply
```

## VERIFY

```powershell
aws stepfunctions describe-state-machine --state-machine-arn <ARN>
aws logs describe-log-groups --log-group-name-prefix /aws/vendedlogs/states/<state-machine>
```

`loggingConfiguration.level=ALL`, `tracingConfiguration.enabled=true`, 로그 그룹의 보존 기간과 과제지 요구가 일치해야 한다. S3 트리거를 켰다면 S3 객체를 하나 올린 뒤 EventBridge 규칙과 state machine execution이 생성되는지 확인한다. 이 검증은 기능 확인이며, 점수 판정은 해당 세트의 공식 채점 절차로 한다.

## 주의

EventBridge가 전달하는 입력은 S3 이벤트 전체다. 기존 ASL이 `$.key`처럼 다른 입력 형식을 기대하면 event target에 input transformer를 추가하거나 ASL을 과제지 요구에 맞게 조정한다. SNS Publish Task와 Map·Parallel·Choice ASL 정의는 이 KIT가 자동 생성하지 않으므로, 문항에 맞는 state 정의를 기존 ASL에 추가한다.
