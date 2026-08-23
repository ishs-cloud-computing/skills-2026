# Lambda 강화 부착 KIT

**기존** Lambda 함수에 X-Ray 추적 · DLQ · 예약 동시성 · 환경변수/코드 CMK · 로그 보존 · VPC 배치 · Function URL · ESM 옵션을 붙인다.

## 이 KIT이 맞나

- 과제지 기존 Lambda 문항 뒤에 **"동시성 제한"·"Function URL"·"DLQ"·"X-Ray"·"환경변수 암호화"** 가 붙었다 → 맞다.
- **함수를 새로 만들어라** → [lambda-get-api](../lambda-get-api/README.md).
- **VPC 안에서 RDS 조회** (task-3) → [lambda-vpc-rds](../lambda-vpc-rds/README.md).
- 아래 블록은 전부 **in-place update**다. 단 `vpc_config` 최초 부착은 ENI 생성으로 1~2분, 제거는 최대 20분 걸린다.

## 세트별 현재 함수 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 함수 리소스 | `aws_lambda_function.book` | `.book_get` | `.get_booking` |
| 함수 이름 | `var.lambda_function_name` | `var.lambda_function_name` | `"unicorn-get-booking-func"` (하드코딩) |
| 실행 역할 | `aws_iam_role.book_lambda` | `aws_iam_role.book_function` | `aws_iam_role.get_booking` |
| 런타임 | `var.lambda_runtime` | `python3.12` | `python3.13` |
| 로그 그룹 | `aws_cloudwatch_log_group.book_lambda` **선생성** | `.book_function` **선생성** | `.get_booking` **선생성** |
| `kms_key_arn` | **없음** | `aws_kms_key.function.arn` | `aws_kms_key.platform.arn` |
| `source_kms_key_arn` | 없음 | `aws_kms_key.function.arn` | 없음 |
| `logging_config` | 없음 | 없음 | **있음** |
| Function URL | 없음 | `aws_lambda_function_url.book_get` (`AWS_IAM`) | 없음 |
| 호출 경로 | ALB 규칙 → `aws_lb_target_group.lambda` (동기) | CloudFront → Function URL (동기) | ALB 규칙 → `aws_lb_target_group.lambda` (동기) |
| 함수 output | **없음** | `lambda_function_url` | **없음** |

**세 세트 모두 로그 그룹을 이미 선생성한다.** `lambda-hardening.tf` 의 `aws_cloudwatch_log_group` 블록은 지우고 기존 것의 `retention_in_days`·`kms_key_id` 만 고친다.

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "lambda_function_name" { value = aws_lambda_function.book.function_name }   # 세트별 주소
output "lambda_role_name"     { value = aws_iam_role.book_lambda.name }
output "lambda_log_group"     { value = aws_cloudwatch_log_group.book_lambda.name }
```

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `lambda-hardening.tf` | `set-XX/task-1/terraform/` | 선생성 로그 그룹 · DLQ(SQS)+SendMessage 정책 · VPC/X-Ray 관리형 정책 부착 |
| `variables.tf` | `variables-lamhard-addon.tf` | `addon_lamhard_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_lamhard_function_name` | **필수** | 대상 함수 이름 |
| `addon_lamhard_role_name` | **필수** | 실행 역할 이름. 직접 참조 권장 |
| `addon_lamhard_log_retention_days` | `30` | 로그 보존 기간(일). 과제지 명시값으로 |
| `addon_lamhard_log_kms_key_arn` | `""` | 로그 그룹 CMK ARN. key policy에 logs 서비스 문장 필수 |
| `addon_lamhard_dlq_name` | `""` | DLQ(SQS) 이름. 빈 문자열이면 생성 안 함 |
| `addon_lamhard_enable_vpc_policy` | `false` | `vpc_config` 를 붙일 때 true |
| `addon_lamhard_enable_xray_policy` | `false` | `tracing_config Active` 를 붙일 때 true |

<details><summary><b>값 뽑기 — 세트별 (tfvars 그대로 붙여넣기)</b></summary>

```powershell
# 위 output 3개를 추가한 뒤
terraform output -raw lambda_function_name
terraform output -raw lambda_role_name
terraform output -raw lambda_log_group
```

```hcl
# 파일: set-02 또는 set-03 의 task-1/terraform/terraform.tfvars
# 이름이 변수라 output 값을 확인해 넣는다
addon_lamhard_function_name = "<terraform output -raw lambda_function_name 값>"
addon_lamhard_role_name     = "<terraform output -raw lambda_role_name 값>"
```

```hcl
# 파일: set-07/task-1/terraform/terraform.tfvars — 이름이 리터럴이라 그대로
addon_lamhard_function_name = "unicorn-get-booking-func"
addon_lamhard_role_name     = "unicorn-get-booking-func-role"
```

같은 루트 모듈이면 tfvars 대신 `aws_lambda_function.<기존>.function_name` · `aws_iam_role.<기존>.name` 직접 참조가 안전하다.
</details>

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # 함수가 update in-place 뿐인지 확인
terraform apply
```

## 1. X-Ray 추적

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_lambda_function 리소스 블록 *안에*
tracing_config {
  mode = "Active"
}
```

역할에 `AWSXRayDaemonWriteAccess` 가 필요하다 — `addon_lamhard_enable_xray_policy = true`.

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 X-Ray가 **없다** — 새로 넣는다.

```powershell
$fn = terraform output -raw lambda_function_name
aws lambda get-function-configuration --function-name $fn --query "TracingConfig"

# 호출 한 번 뒤 트레이스 확인 (반영에 1~2분)
aws xray get-trace-summaries `
  --start-time (Get-Date).AddMinutes(-10).ToUniversalTime().ToString("s") `
  --end-time (Get-Date).ToUniversalTime().ToString("s") --query "TraceSummaries[].Id"
```
</details>

## 2. 예약 동시성

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_lambda_function 리소스 블록 *안에*
reserved_concurrent_executions = 10
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 미설정(무제한)이다. **계정 미예약 동시성 100을 남겨야 한다** — 작은 값(≤10)으로 쓴다.

```powershell
$fn = terraform output -raw lambda_function_name
aws lambda get-function-concurrency --function-name $fn
aws lambda get-account-settings --query "AccountLimit.ConcurrentExecutions"
```
</details>

## 3. 환경변수·코드 CMK 암호화

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_lambda_function 리소스 블록 *안에*
kms_key_arn        = aws_kms_key.function.arn   # 환경변수 at-rest
source_kms_key_arn = aws_kms_key.function.arn   # zip 코드 at-rest ("코드 암호화" 요구 시)
```

실행 역할에 `kms:Decrypt`·`kms:DescribeKey` 가 필요하다 (set-07 task-1 `lambda.tf` 의 `Kms` 문장).

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 현재 | 쓸 키 | 키 ARN output |
| --- | --- | --- | --- |
| set-02 | **둘 다 없음** | `aws_kms_key.s3` 재사용 또는 addon CMK 신설 | **없음** |
| set-03 | `kms_key_arn` + `source_kms_key_arn` **둘 다 있음** | `aws_kms_key.function` | `function_kms_arn` (있음) |
| set-07 | `kms_key_arn` 만 | `aws_kms_key.platform` | `platform_kms_arn` (있음) |

```powershell
terraform output -raw function_kms_arn      # set-03
terraform output -raw platform_kms_arn      # set-07

$fn = terraform output -raw lambda_function_name
aws lambda get-function-configuration --function-name $fn --query "[KMSKeyArn,Environment.Variables]"
```

`kms_key_arn` 만으로는 환경변수가 콘솔에 **암호문으로 보이지 않는다**(at-rest 암호화일 뿐). 채점이 "환경변수 값 자체가 암호문"을 기대하면 **set-03 task-1 `lambda.tf` 의 `aws_kms_ciphertext.table_name`** 패턴을 복사한다:

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
resource "aws_kms_ciphertext" "table_name" {
  key_id    = aws_kms_key.function.key_id
  plaintext = aws_dynamodb_table.book.name
}
# environment.variables 안에서
TABLE_NAME_ENC = aws_kms_ciphertext.table_name.ciphertext_blob
```

`source_kms_key_arn` 은 **zip 배포 함수에만** 적용된다.
</details>

## 4. 로그 그룹 보존·암호화 · logging_config

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_cloudwatch_log_group 리소스 블록 *안에*
retention_in_days = 30
kms_key_id        = aws_kms_key.function.arn
```

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_lambda_function 리소스 블록 *안에*
logging_config {
  log_format = "Text"    # JSON 요구 시 "JSON" + application_log_level / system_log_level
  log_group  = aws_cloudwatch_log_group.book_lambda.name   # ← 세트별 주소
}

depends_on = [aws_cloudwatch_log_group.book_lambda]
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 로그 그룹 리소스 | 선언 위치 | `logging_config` |
| --- | --- | --- | --- |
| set-02 | `aws_cloudwatch_log_group.book_lambda` | `lambda.tf` | 없음 |
| set-03 | `aws_cloudwatch_log_group.book_function` | `lambda.tf` | 없음 |
| set-07 | `aws_cloudwatch_log_group.get_booking` | `lambda.tf` | **이미 있음** |

```powershell
$lg = terraform output -raw lambda_log_group
aws logs describe-log-groups --log-group-name-prefix $lg `
  --query "logGroups[].[logGroupName,retentionInDays,kmsKeyId]"
aws logs tail $lg --since 10m
```

로그 그룹 CMK는 key policy에 `logs.<region>.amazonaws.com` 문장이 **필수**다 ([kms](../kms/README.md) 3번). 없으면 로그 그룹 생성이 AccessDenied로 실패한다.
</details>

## 5. DLQ (비동기 호출 실패분)

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_lambda_function 리소스 블록 *안에*
dead_letter_config {
  target_arn = aws_sqs_queue.addon_lamhard_dlq[0].arn   # SNS 토픽 ARN 도 가능(역할에 sns:Publish)
}
```

<details><summary><b>값 뽑기 — 세트별 (세 세트 다 동기 호출이라 적용 안 된다)</b></summary>

`dead_letter_config` 는 **비동기 호출**(S3·SNS·EventBridge)에서만 동작한다. 세 세트의 호출 경로는 전부 **동기**다:

| 세트 | 호출 경로 | DLQ 적용 |
| --- | --- | --- |
| set-02 | ALB 리스너 규칙 → Lambda 타깃그룹 | **안 됨** |
| set-03 | CloudFront → Function URL | **안 됨** |
| set-07 | ALB 리스너 규칙 → Lambda 타깃그룹 | **안 됨** |

과제지가 DLQ를 요구하면 비동기 트리거(EventBridge 등)를 같이 붙이는 문항일 가능성이 높다 — 문장을 다시 읽는다.

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "lambda_dlq_url" { value = aws_sqs_queue.addon_lamhard_dlq[0].url }
```

```powershell
aws lambda get-function-configuration --function-name (terraform output -raw lambda_function_name) `
  --query "DeadLetterConfig"
aws sqs get-queue-attributes --queue-url (terraform output -raw lambda_dlq_url) `
  --attribute-names ApproximateNumberOfMessages
```
</details>

## 6. VPC 배치

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_lambda_function 리소스 블록 *안에*
vpc_config {
  subnet_ids         = [for k in local.private_subnet_keys : aws_subnet.this[k].id]
  security_group_ids = [aws_security_group.addon_lambda.id]
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 서브넷이 `aws_subnet.this[k]` 맵이고 `private_subnet_ids` output이 **이미 있다** (map):

```powershell
terraform output -json private_subnet_ids
# → {"priv-a":"subnet-...","priv-c":"subnet-..."}
$subnets = (terraform output -json private_subnet_ids | ConvertFrom-Json).PSObject.Properties.Value

aws lambda get-function-configuration --function-name (terraform output -raw lambda_function_name) `
  --query "VpcConfig"
```

SG는 새로 만든다(아웃바운드만). NAT 경유 인터넷 없이 DynamoDB에 붙으려면 엔드포인트가 필요하다 → [vpc-endpoints](../vpc-endpoints/README.md).

**`vpc_config` 최초 부착은 ENI 생성으로 1~2분, 제거는 최대 20분** 걸린다. 시간이 없으면 마지막에 붙인다.
</details>

## 7. Function URL

함수 하나에 URL은 하나뿐이다. **set-03은 이미 `aws_lambda_function_url.book_get` 이 있으니 이 블록을 붙이지 말고 기존 것의 `authorization_type` 만 고친다.**

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf  (set-02 · set-07 처럼 URL이 없을 때만)
resource "aws_lambda_function_url" "addon" {
  function_name      = aws_lambda_function.book.function_name   # ← 세트별 주소
  authorization_type = "NONE"   # CloudFront OAC 뒤면 "AWS_IAM"
}
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "addon_lambda_function_url" {
  value = aws_lambda_function_url.addon.function_url
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 현재 | 비고 |
| --- | --- | --- |
| set-02 | 없음 | ALB 경유. 추가하면 경로가 둘이 된다 |
| set-03 | `aws_lambda_function_url.book_get` (`AWS_IAM`) **이미 있음** | output `lambda_function_url` 존재. CloudFront OAC + `aws_lambda_permission.cloudfront` 짝 |
| set-07 | 없음 | ALB 경유 |

```powershell
terraform output -raw lambda_function_url          # set-03
terraform output -raw addon_lambda_function_url    # 새로 만든 경우

# AWS_IAM 이면 SigV4 서명이 필요해 curl 로는 403 이 정상
curl.exe -s -o NUL -w "%{http_code}`n" (terraform output -raw lambda_function_url)
```

**`authorization_type = "NONE"` 은 인터넷 공개다.** CloudFront 경유만 허용하면 `AWS_IAM` + OAC — set-03 `lambda.tf` 의 `aws_lambda_permission.cloudfront` 가 완성본이다.
</details>

<details><summary><b>ESM 옵션 — task-1 세 세트에는 이벤트 소스 매핑이 없다</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf
# 기존 aws_lambda_event_source_mapping 리소스 블록 *안에*
batch_size                         = 10
maximum_batching_window_in_seconds = 5

# 스트림(Kinesis·DDB Streams·MSK) 전용 — SQS 에 넣으면 InvalidParameterValue
starting_position              = "LATEST"     # 또는 "TRIM_HORIZON"
maximum_retry_attempts         = 2
bisect_batch_on_function_error = true
maximum_record_age_in_seconds  = 3600

destination_config {
  on_failure {
    destination_arn = aws_sqs_queue.addon_lamhard_dlq[0].arn
  }
}

filter_criteria {
  filter {
    pattern = jsonencode({ body = { type = ["alert"] } })   # SQS=body, DDB Streams=dynamodb, Kinesis=data
  }
}
```

```powershell
aws lambda list-event-source-mappings --function-name (terraform output -raw lambda_function_name) `
  --query "EventSourceMappings[].[UUID,State,BatchSize,StartingPosition]"
```

DynamoDB Streams를 붙이는 경우는 [dynamodb-hardening](../dynamodb-hardening/README.md) 5번이 완성 블록이다.
</details>

## VERIFY

```powershell
$fn = terraform output -raw lambda_function_name
aws lambda get-function-configuration --function-name $fn `
  --query "[TracingConfig,KMSKeyArn,DeadLetterConfig,VpcConfig.VpcId,LoggingConfig]"
aws lambda get-function-concurrency --function-name $fn
aws logs tail (terraform output -raw lambda_log_group) --since 10m
```

## TROUBLESHOOT

- 위 블록은 전부 **in-place**. `vpc_config` 부착만 1~2분, 제거는 최대 20분.
- `reserved_concurrent_executions` 는 계정 미예약 동시성 100을 남겨야 한다.
- **`dead_letter_config` 는 비동기 호출에서만 동작한다.** ALB·API GW·Function URL(동기)·ESM(폴링)에는 적용되지 않는다.
- `source_kms_key_arn` 은 zip 배포 함수에만. 컨테이너 이미지 함수면 ECR 암호화.
- `kms_key_arn` 만으로는 환경변수가 암호문으로 보이지 않는다 — `aws_kms_ciphertext` 패턴(set-03).
- 로그 그룹 CMK는 key policy에 logs 서비스 문장이 필수다.
- 이미 Lambda가 `/aws/lambda/<함수>` 를 자동 생성했으면 선생성 apply가 `ResourceAlreadyExistsException` — `terraform import aws_cloudwatch_log_group.addon_lamhard /aws/lambda/<함수>`.
- ESM `starting_position`·`bisect_batch_on_function_error`·`maximum_retry_attempts`·`destination_config` 는 **스트림 소스 전용**이다.
- Function URL `NONE` 은 인터넷 공개다.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/lambda.tf` — 선생성 로그 그룹(CMK) · `kms_key_arn` · `logging_config`
- set-03 task-1 `terraform/lambda.tf` — `source_kms_key_arn` · Function URL(AWS_IAM) · CloudFront 권한 · `aws_kms_ciphertext`
- set-02 task-2 module-3-msk `terraform/lambda.tf` — MSK ESM (`starting_position`·`topics`)

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
