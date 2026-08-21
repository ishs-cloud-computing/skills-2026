# lambda-hardening 부착 스니펫

1과제 옵션 "Lambda GET API"·Security 의 확장 문항(X-Ray 추적·DLQ·예약 동시성·환경변수 CMK·로그 보존·VPC 배치·
Function URL·이벤트 소스 옵션)을 **기존 Lambda 함수**에 붙인다. 전 세트 Lambda 문항 확장 대응
(set-02/03/05/07 task-1, set-02 m4, set-08 m3).

## RUN guard

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체를 `init`/`apply` 하지 않으므로 기존 Kit의 state를 건드리지 않는다.

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

- **VERIFY** = 이 README의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 이 README에는 이 KIT 고유 문제만 둔다.

## 파일

- `lambda-hardening.tf` — 선생성 로그 그룹, DLQ(SQS)+SendMessage 정책, VPC·X-Ray 관리형 정책 부착. 기존 함수·역할 이름을 변수로 받는다.
- `variables.tf` — `addon_lamhard_*` 변수.
- 함수 블록 **안에** 넣는 인자와 Function URL·ESM 옵션은 아래 `## 블록` 을 복사한다.

## 부착 절차

1. 두 `.tf` 를 `set-XX/task-1/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 주입:

   ```hcl
   addon_lamhard_function_name      = "unicorn-get-booking-func"
   addon_lamhard_role_name          = "unicorn-get-booking-func-role"
   addon_lamhard_log_retention_days = 30
   addon_lamhard_dlq_name           = ""    # 과제지가 DLQ 요구 시 이름
   addon_lamhard_enable_vpc_policy  = false # vpc_config 붙이면 true
   addon_lamhard_enable_xray_policy = false # tracing_config 붙이면 true
   ```

   기존 리소스를 직접 참조하려면 `var.addon_lamhard_role_name` 을 `aws_iam_role.<기존>.name` 으로 바꾼다.
3. 기존 세트가 이미 `/aws/lambda/<함수>` 로그 그룹을 만들었으면(set-02/03/08) `lambda-hardening.tf` 의
   `aws_cloudwatch_log_group` 블록을 지우고 기존 것에 `retention_in_days`·`kms_key_id` 만 고친다.
4. 필요한 블록을 기존 `aws_lambda_function` 안에 추가한다(아래).
5. `terraform fmt` → `validate` → `plan` 으로 기존 리소스 diff 가 함수 in-place update 뿐인지 확인 → `apply`.

## 블록

### X-Ray 추적

```hcl
# aws_lambda_function 리소스 안에:
tracing_config {
  mode = "Active"
}
```

`addon_lamhard_enable_xray_policy = true` (역할에 `AWSXRayDaemonWriteAccess`).

### DLQ (비동기 호출 실패분)

```hcl
# aws_lambda_function 리소스 안에:
dead_letter_config {
  target_arn = aws_sqs_queue.addon_lamhard_dlq[0].arn # SNS 토픽 ARN 도 가능(역할에 sns:Publish)
}
```

### 예약 동시성

```hcl
# aws_lambda_function 리소스 안에:
reserved_concurrent_executions = 10
```

### 환경변수·코드 CMK 암호화

```hcl
# aws_lambda_function 리소스 안에:
kms_key_arn        = aws_kms_key.<기존>.arn # 환경변수 at-rest
source_kms_key_arn = aws_kms_key.<기존>.arn # zip 코드 at-rest ("코드 암호화" 까지 요구할 때)
```

실행 역할에 `kms:Decrypt`·`kms:DescribeKey` (set-07 task-1 `lambda.tf` `Kms` 문장).

### 로그 그룹 연결 (선생성 + retention)

```hcl
# aws_lambda_function 리소스 안에:
logging_config {
  log_format = "Text" # JSON 요구 시 "JSON" + application_log_level/system_log_level
  log_group  = aws_cloudwatch_log_group.addon_lamhard.name
}

depends_on = [aws_cloudwatch_log_group.addon_lamhard]
```

### VPC 배치

```hcl
# aws_lambda_function 리소스 안에:
vpc_config {
  subnet_ids         = [aws_subnet.<private-a>.id, aws_subnet.<private-b>.id]
  security_group_ids = [aws_security_group.<lambda>.id]
}
```

`addon_lamhard_enable_vpc_policy = true` (ENI 생성 권한). SG 는 egress 만 있으면 된다(set-05 task-1 `lambda.tf`).

### Function URL

```hcl
# 새 블록 (lambda.tf 끝에):
resource "aws_lambda_function_url" "addon" {
  function_name      = aws_lambda_function.<기존>.function_name
  authorization_type = "NONE" # CloudFront OAC 뒤면 "AWS_IAM" + lambda-get-api 키트 (b) 블록
}

output "addon_lamhard_function_url" {
  value = aws_lambda_function_url.addon.function_url
}
```

### 이벤트 소스 매핑 옵션 (SQS / Kinesis / DynamoDB Streams / MSK)

```hcl
# 기존 aws_lambda_event_source_mapping 리소스 안에:
batch_size                         = 10
maximum_batching_window_in_seconds = 5

# 스트림(Kinesis·DDB Streams·MSK) 전용 — SQS 에 넣으면 오류
starting_position              = "LATEST" # 또는 "TRIM_HORIZON"
maximum_retry_attempts         = 2
bisect_batch_on_function_error = true
maximum_record_age_in_seconds  = 3600

# 스트림 전용 실패 목적지 (SQS 소스는 큐의 redrive_policy 로 DLQ 지정)
destination_config {
  on_failure {
    destination_arn = aws_sqs_queue.addon_lamhard_dlq[0].arn
  }
}

# 이벤트 필터 (SQS·Kinesis·DDB Streams·MSK 공통)
filter_criteria {
  filter {
    pattern = jsonencode({ body = { type = ["alert"] } }) # SQS=body, DDB Streams=dynamodb, Kinesis=data
  }
}
```

`destination_config.on_failure` 대상이 SQS 면 역할에 `sqs:SendMessage`, SNS 면 `sns:Publish`.

## 함정

- 위 블록은 전부 **in-place update**. 단 `vpc_config` 최초 부착은 ENI 생성으로 apply 1~2분, 제거는 ENI 정리로 최대 20분.
- `reserved_concurrent_executions` 는 계정 미예약 동시성 100 을 남겨야 한다 — 작은 값(≤10)으로.
- `dead_letter_config` 는 **비동기 호출**(S3·SNS·EventBridge)에서만 동작. ALB·API GW·Function URL(동기)·ESM(폴링) 에는 적용되지 않는다 — SQS/Kinesis 트리거 실패 처리는 ESM `destination_config` 또는 SQS `redrive_policy`.
- `source_kms_key_arn` 은 zip 배포 함수에만. 컨테이너 이미지 함수면 ECR 암호화.
- `kms_key_arn` 만으로는 환경변수가 콘솔에 암호문으로 보이지 않는다(at-rest). 채점이 "환경변수 값이 암호문" 을 기대하면 set-03 task-1 `lambda.tf` 의 `aws_kms_ciphertext` 패턴.
- 로그 그룹 CMK 는 key policy 에 `logs.<region>.amazonaws.com` 문장 필수(kms 키트). 없으면 로그 그룹 생성이 AccessDenied.
- 이미 Lambda 가 `/aws/lambda/<함수>` 를 자동 생성했으면 선생성 apply 가 `ResourceAlreadyExistsException` — `terraform import aws_cloudwatch_log_group.addon_lamhard /aws/lambda/<함수>`.
- ESM `starting_position`·`bisect_batch_on_function_error`·`maximum_retry_attempts`·`destination_config` 는 **스트림 소스 전용** — SQS ESM 에 넣으면 InvalidParameterValue.
- `AWSLambdaVPCAccessExecutionRole` 은 Logs 권한도 포함 — 최소권한 채점이면 인라인 `ec2:CreateNetworkInterface`·`ec2:DescribeNetworkInterfaces`·`ec2:DeleteNetworkInterface` 로 대체(set-05 task-1 `lambda.tf` `VpcEni` 문장).
- Function URL `authorization_type = "NONE"` 은 인터넷 공개 — 과제지가 CloudFront 경유만 허용하면 `AWS_IAM` + OAC(lambda-get-api 키트).

## 실전 구현 (참고용)

- `set-07/task-1/terraform/lambda.tf` — 선생성 로그 그룹(CMK)·`kms_key_arn`·`logging_config`
- `set-03/task-1/terraform/lambda.tf` — `source_kms_key_arn`·Function URL(AWS_IAM)·CloudFront 권한
- `set-05/task-1/terraform/lambda.tf` — `vpc_config` + 인라인 ENI 권한 + Lambda SG
- `set-02/task-2/module-4-msk/terraform/lambda.tf` — MSK ESM(`starting_position`·`topics`)
- `set-08/task-2/module-3-event-handling/terraform/lambda.tf` — 선생성 로그 그룹 retention + 최소권한 인라인
