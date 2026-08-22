# Step Functions hardening KIT

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 Step Functions state machine에 **CloudWatch Logs 전달**, X-Ray tracing, 선택적 SNS Publish와 S3 Object Created → EventBridge → `StartExecution` 흐름을 부착하는 COPY KIT이다. 이 디렉터리는 독립 Terraform state나 독립 `apply` 대상이 아니다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 2개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_sfnhard_state_machine_name` | **필수** | 기존 state machine 이름. 로그 그룹·규칙 이름의 접두이자 EventBridge 대상 ARN 조립에 쓴다 |
| `addon_sfnhard_role_name` | **필수** | 기존 state machine 실행 역할 이름. 로그 전달·X-Ray·SNS Publish 정책이 여기 붙는다 |
| `addon_sfnhard_log_retention_days` | `7` | 로그 그룹 보존 기간(일) |
| `addon_sfnhard_sns_topic_arn` | `""` | SNS Publish Task 대상 토픽 ARN. 비우면 sns:Publish 문장 생략 |
| `addon_sfnhard_s3_bucket_name` | `""` | Object Created 로 state machine 을 시작할 기존 버킷 이름. 비우면 EventBridge 규칙 생성 안 함 |
| `addon_sfnhard_s3_key_prefix` | `"input/"` | 트리거 대상 키 접두 (예: input/). 빈 문자열이면 전체 |

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

## TROUBLESHOOT — 주의
EventBridge가 전달하는 입력은 S3 이벤트 전체다. 기존 ASL이 `$.key`처럼 다른 입력 형식을 기대하면 event target에 input transformer를 추가하거나 ASL을 과제지 요구에 맞게 조정한다. SNS Publish Task와 Map·Parallel·Choice ASL 정의는 이 KIT가 자동 생성하지 않으므로, 문항에 맞는 state 정의를 기존 ASL에 추가한다.
