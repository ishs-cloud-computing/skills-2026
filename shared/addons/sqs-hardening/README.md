# sqs-hardening 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 SQS 큐에 DLQ(redrive)·SSE(SQS 관리 키 또는 CMK)·visibility timeout 을 붙이고,
DLQ 와 redrive allow policy 를 새 리소스로 만든다. set-05 m1, set-07 m3, set-08 m4(KEDA 큐), set-02 m1(Lambda DLQ) 후보에 대응.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 1개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_sqs_source_queue_arn` | **필수** | 이 DLQ 로 보낼 기존 소스 큐 ARN (aws_sqs_queue.<기존>.arn). redrive allow policy 에 들어간다 |
| `addon_sqs_dlq_name` | `"skills-queue-dlq"` | DLQ 이름. 과제지 명시 이름과 정확히 일치. FIFO 소스 큐면 .fifo 로 끝나야 하고 fifo_queue = true 추가 |
| `addon_sqs_max_receive_count` | `3` | 소스 큐 redrive_policy 의 maxReceiveCount — 이 횟수만큼 수신 후 DLQ 로 이동 (README 블록에서 사용) |
| `addon_sqs_dlq_retention_seconds` | `1209600` | DLQ 메시지 보존 (초). 소스 큐보다 길게 — 기본 14일 최대값 |
| `addon_sqs_kms_key_id` | `""` | SSE-KMS CMK ID/ARN/alias. 빈 문자열이면 SSE-SQS(sqs_managed_sse_enabled = true) |
| `addon_sqs_visibility_timeout_seconds` | `30` | 소스 큐 visibility timeout (초). Lambda 소비면 함수 timeout 의 6배 권장 (README 블록에서 사용) |

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

## FAST — terraform 없이 CLI 로 붙이기

큐 속성은 전부 in-place 다.

**대가**: terraform state 와 실물이 어긋난다. 이 세트에 이후 `apply` 를 걸면 되돌아가므로,
CLI 로 붙였으면 그 세트는 더 apply 하지 않거나 나중에 같은 값을 `.tf` 에도 넣는다.

```powershell
$Q   = aws sqs get-queue-url --queue-name <큐> --query QueueUrl --output text
$DLQ = aws sqs get-queue-url --queue-name <DLQ> --query QueueUrl --output text
$DLQARN = aws sqs get-queue-attributes --queue-url $DLQ --attribute-names QueueArn `
  --query 'Attributes.QueueArn' --output text

# 값 안에 JSON 이 들어가는 속성(RedrivePolicy·Policy)은 shorthand 로 못 넣는다 -> file://
@"
{
  "VisibilityTimeout": "60",
  "MessageRetentionPeriod": "345600",
  "KmsMasterKeyId": "alias/<별칭>",
  "RedrivePolicy": "{\"deadLetterTargetArn\":\"$DLQARN\",\"maxReceiveCount\":\"3\"}"
}
"@ | Set-Content -Encoding utf8 sqs-attrs.json

aws sqs set-queue-attributes --queue-url $Q --attributes file://sqs-attrs.json
aws sqs get-queue-attributes --queue-url $Q --attribute-names All
```

- **`RedrivePolicy` 의 값은 JSON 문자열이다** — 객체가 아니라 이스케이프된 문자열이어야 한다. 위 형태 그대로 쓴다.
- `--attributes Key=Value` shorthand 는 JSON 값을 못 받는다. 에러 메시지가 원인을 안 알려주니 처음부터 `file://` 로 간다.
- DLQ 는 **원본 큐와 타입이 같아야 한다** (FIFO 원본에는 FIFO DLQ).

## VERIFY / SCORE

- **VERIFY** = 이 README 본문의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 아래 함정은 이 KIT 고유 문제다.

## 파일

- `sqs.tf` — `aws_sqs_queue` DLQ(SSE·보존) · `aws_sqs_queue_redrive_allow_policy`(byQueue, 소스 큐 1개)
- `variables.tf` — `addon_sqs_*` 변수. `max_receive_count`·`visibility_timeout_seconds` 는 README 블록(기존 큐 안)에서 쓴다

## 부착 절차

1. `sqs.tf`·`variables.tf` 를 `set-XX/task-2/module-N-<name>/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 같은 루트 모듈이면 `var.addon_sqs_source_queue_arn` 을 `aws_sqs_queue.<기존>.arn` 으로 바꾼다.

   ```hcl
   addon_sqs_dlq_name                   = "skills-worker-queue-dlq"
   addon_sqs_source_queue_arn           = "arn:aws:sqs:ap-northeast-2:123456789012:skills-worker-queue"
   addon_sqs_max_receive_count          = 3
   addon_sqs_dlq_retention_seconds      = 1209600
   addon_sqs_kms_key_id                 = ""     # CMK 요구 시 alias/... 또는 ARN
   addon_sqs_visibility_timeout_seconds = 30
   ```
3. 아래 "블록" 을 `aws_sqs_queue.<기존>` 안에 붙인다.
4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 큐가 `update in-place` 인지 확인 → `terraform apply`.
5. 검증:

   ```powershell
   aws sqs get-queue-attributes --queue-url <소스 큐 URL> --attribute-names RedrivePolicy VisibilityTimeout SqsManagedSseEnabled KmsMasterKeyId
   aws sqs get-queue-attributes --queue-url <DLQ URL> --attribute-names RedriveAllowPolicy MessageRetentionPeriod SqsManagedSseEnabled KmsMasterKeyId
   ```

## 블록

```hcl
# aws_sqs_queue 리소스(기존 소스 큐) 안에: DLQ 연결 (in-place)
redrive_policy = jsonencode({
  deadLetterTargetArn = aws_sqs_queue.addon_dlq.arn
  maxReceiveCount     = var.addon_sqs_max_receive_count
})
```

```hcl
# aws_sqs_queue 리소스 안에: 암호화 (in-place) — 둘 중 하나만
sqs_managed_sse_enabled = true                  # SSE-SQS (기본 신규 큐는 이미 켜져 있음)
# kms_master_key_id     = var.addon_sqs_kms_key_id   # CMK 요구 시 — 위 줄은 지운다
```

```hcl
# aws_sqs_queue 리소스 안에: visibility timeout (in-place)
visibility_timeout_seconds = var.addon_sqs_visibility_timeout_seconds
```

```hcl
# aws_lambda_function 리소스 안에: Lambda 비동기 호출 실패 DLQ (set-02 m1 류) — Role 에 sqs:SendMessage 필요
dead_letter_config {
  target_arn = aws_sqs_queue.addon_dlq.arn
}
```

KEDA / worker IAM 정책에 DLQ 도 추가 — redrive 는 SQS 내부 동작이라 권한이 필요 없지만, 워커가 DLQ 를 직접 읽거나 KEDA 가 DLQ 길이로도 스케일하면 기존 정책 `resources` 에 `aws_sqs_queue.addon_dlq.arn` 을 넣는다:

```hcl
# 기존 aws_iam_policy_document 의 sqs statement resources 에:
resources = [aws_sqs_queue.<기존>.arn, aws_sqs_queue.addon_dlq.arn]
```

## TROUBLESHOOT — 이 KIT 고유 함정
- 블록은 전부 in-place. 큐 `name`·`fifo_queue` 변경은 ⚠ 재생성이며 같은 이름은 삭제 후 60초 동안 다시 못 만든다.
- DLQ 는 소스 큐와 **같은 타입·같은 리전·같은 계정**. FIFO 소스면 DLQ 도 `.fifo` + `fifo_queue = true`.
- `sqs_managed_sse_enabled` 와 `kms_master_key_id` 는 배타 — 둘 다 쓰면 plan 에서 충돌하거나 apply 가 SSE-SQS 를 조용히 끈다. 스니펫 DLQ 는 `addon_sqs_kms_key_id` 유무로 자동 선택.
- CMK 큐에 **다른 서비스가 메시지를 넣으면**(SNS → SQS, S3 이벤트, EventBridge) key policy 에 그 서비스 principal 의 `kms:GenerateDataKey`·`kms:Decrypt` 가 필요 — 없으면 메시지가 조용히 버려진다. KEDA 의 `GetQueueAttributes` 는 복호화가 없어 키 권한 불필요. 워커 ReceiveMessage 는 `kms:Decrypt` 필요.
- `visibility_timeout_seconds` 는 Lambda ESM 소비면 함수 timeout 이상(권장 6배) — 작으면 같은 메시지가 중복 처리되고 `maxReceiveCount` 를 금방 채워 DLQ 로 간다. KEDA `queueLength` 는 기본 visible 메시지만 세므로(`scaleOnInFlight` 기본 true 는 in-flight 포함 — 버전별 확인 필요) timeout 을 늘리면 스케일 지표가 달라진다.
- set-08 m4 채점 4-2 가 소스 큐 `VisibilityTimeout` 을 정확 일치로 본다 — 과제지 값을 바꾸지 않는다. 채점이 `RedrivePolicy` 를 JSON 문자열 비교하면 `maxReceiveCount` 타입(숫자)을 맞춘다.
- redrive allow policy 는 `byQueue` 최대 10개 소스. 소스 큐가 여럿이면 `sourceQueueArns` 를 늘리거나 리소스를 지워 `allowAll` 로 둔다. `denyAll` 이면 소스 큐 `redrive_policy` apply 가 실패한다.
- DLQ 보존 기간은 소스 큐보다 길어야 의미가 있다(메시지 나이는 원래 큐 도착 시각 기준). 기본 14일.
- Lambda `dead_letter_config` 는 **비동기 호출**(SNS·S3·EventBridge 트리거)만 적용된다. SQS ESM 소비의 실패는 소스 큐 `redrive_policy` 가 맡고, ESM `destination_config.on_failure` 는 별개.

## 실전 구현 (참고용)

- set-08 task-2 module-4-sqs-scaling `terraform/sqs.tf`(visibility_timeout 변수)
- set-05 task-2 module-1-eks-scaling `terraform/sqs.tf`, set-07 task-2 module-3-eks-scaling `terraform/sqs.tf`(KEDA 트리거 큐, 기본값)
- DLQ·SSE·redrive allow policy 실전 구현 없음
