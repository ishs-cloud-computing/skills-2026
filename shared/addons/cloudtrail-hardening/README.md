# CloudTrail 부착 KIT

로그 무결성 검증 · 멀티 리전 추적 · 선택적 CloudWatch Logs 연동 · SSE-KMS.

## 이 KIT이 맞나

- 과제지에 **"CloudTrail"·"API 호출 감사"·"로그 무결성 검증"** → 맞다.
- **VPC 트래픽 로그** → [vpc-flow-log](../vpc-flow-log/README.md) · **감사 Role** → [iam-audit-role](../iam-audit-role/README.md).
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 현재 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| CloudTrail | **없음** | **없음** | **없음** |
| 로그 버킷 | — | — | — |
| `account_id` output | 있음 | 있음 | 있음 |
| 쓸 수 있는 CMK | `aws_kms_key.s3` | `aws_kms_key.bucket` | `aws_kms_key.data` |

**세 세트 모두 CloudTrail이 없다.** 나오면 이 KIT이 유일한 재료다 — 실전 구현이 저장소에 없으니 `plan` 을 특히 꼼꼼히 읽는다.

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `cloudtrail.tf` | `set-XX/task-1/terraform/` | 로그 S3 버킷 + 버킷 정책 · `aws_cloudtrail` · 선택적 CloudWatch Logs·CMK |
| `variables.tf` | `variables-trail-addon.tf` | `addon_trail_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_trail_name` | **필수** | **채점이 `describe-trails` 로 직접 읽는다.** 과제지와 정확히 일치 |
| `addon_trail_bucket_prefix` | `"cloudtrail-logs"` | 로그 버킷 접두 (`<prefix>-<account_id>`, **전역 유일**) |
| `addon_trail_s3_key_prefix` | `""` | 버킷 안 key prefix. 버킷 정책 경로는 자동으로 맞춰진다 |
| `addon_trail_multi_region` | `false` | 과제지 "모든 리전" 요구 시 true |
| `addon_trail_include_global_events` | `true` | IAM·STS·CloudFront 등 글로벌 이벤트 |
| `addon_trail_read_write_type` | `"All"` | All / ReadOnly / WriteOnly |
| `addon_trail_cw_logs_enabled` | `false` | 메트릭 필터·알람 문항이 같이 나오면 true |
| `addon_trail_log_group_name` | `"/aws/cloudtrail/trail"` | 로그 그룹 이름 |
| `addon_trail_log_retention_days` | `30` | 보존 기간 |
| `addon_trail_kms_enabled` | `false` | SSE-KMS CMK 생성·적용 |
| `addon_trail_kms_alias` | `"cloudtrail-logs"` | CMK alias (`alias/` 제외) |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## 1. Trail 본체

```hcl
# 파일: set-XX/task-1/terraform/cloudtrail.tf   (KIT에서 복사됨)
resource "aws_cloudtrail" "addon" {
  name                          = var.addon_trail_name
  s3_bucket_name                = aws_s3_bucket.addon_trail.id
  s3_key_prefix                 = var.addon_trail_s3_key_prefix
  enable_log_file_validation    = true                                  # 무결성 검증
  is_multi_region_trail         = var.addon_trail_multi_region
  include_global_service_events = var.addon_trail_include_global_events

  event_selector {
    read_write_type           = var.addon_trail_read_write_type
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.addon_trail]
}
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "trail_name"       { value = aws_cloudtrail.addon.name }
output "trail_arn"        { value = aws_cloudtrail.addon.arn }
output "trail_bucket"     { value = aws_s3_bucket.addon_trail.id }
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 새로 만든다. 로그 버킷 이름은 **전역 유일**해야 하므로 계정 ID를 붙인다:

```powershell
terraform output -raw account_id        # 세 세트 모두 있음
terraform output -raw trail_bucket
terraform output -raw trail_name

aws cloudtrail describe-trails --trail-name-list (terraform output -raw trail_name) `
  --query "trailList[].[Name,IsMultiRegionTrail,LogFileValidationEnabled,IncludeGlobalServiceEvents,S3BucketName]"
aws cloudtrail get-trail-status --name (terraform output -raw trail_name) `
  --query "[IsLogging,LatestDeliveryTime]"
aws cloudtrail get-event-selectors --trail-name (terraform output -raw trail_name)

# 로그가 실제로 떨어지는지 (첫 파일까지 최대 15분)
aws s3 ls "s3://$(terraform output -raw trail_bucket)/AWSLogs/" --recursive | Select-Object -First 5
```

`IsLogging=true`, `LogFileValidationEnabled=true` 와 과제지의 멀티 리전·글로벌 이벤트 값이 일치해야 한다.

**기존 세트 버킷(`s3_bucket_name`)을 재사용하지 않는다** — 정적 호스팅 버킷에 OAC 정책이 이미 있어 CloudTrail 서비스 문장을 수동으로 합쳐야 하고, 채점 대상 버킷을 오염시킨다.
</details>

## 2. CloudWatch Logs 연동

```hcl
# 파일: set-XX/task-1/terraform/cloudtrail.tf
# 기존 aws_cloudtrail 리소스 블록 *안에*
cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.addon_trail[0].arn}:*"
cloud_watch_logs_role_arn  = aws_iam_role.addon_trail_cw[0].arn
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "trail_log_group" { value = aws_cloudwatch_log_group.addon_trail[0].name }
```

```powershell
terraform output -raw trail_log_group
aws logs tail (terraform output -raw trail_log_group) --since 20m | Select-Object -First 5

aws cloudtrail describe-trails --trail-name-list (terraform output -raw trail_name) `
  --query "trailList[].[CloudWatchLogsLogGroupArn,CloudWatchLogsRoleArn]"
```

**`cloud_watch_logs_group_arn` 은 끝에 `:*` 가 붙어야 한다** — 안 붙이면 `InvalidCloudWatchLogsLogGroupArnException`.

로그 그룹이 생기면 메트릭 필터·알람을 붙일 수 있다 → [cw-alarms](../cw-alarms/README.md) 1번. ConsoleLogin 실패·루트 사용 감지 같은 문항이 여기 딸려 온다.
</details>

## 3. SSE-KMS

```hcl
# 파일: set-XX/task-1/terraform/cloudtrail.tf
# 기존 aws_cloudtrail 리소스 블록 *안에*
kms_key_id = aws_kms_key.addon_trail[0].arn
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

새 CMK를 만드는 대신 세트 기존 키를 쓸 수도 있다 — 단 **key policy에 CloudTrail·CloudWatch Logs 서비스 문장을 합쳐야 한다.**

| 세트 | 재사용 후보 | 키 ARN output |
| --- | --- | --- |
| set-02 | `aws_kms_key.s3` | **없음** — [kms](../kms/README.md) 0번에서 노출 |
| set-03 | `aws_kms_key.bucket` | `bucket_kms_arn` (있음) |
| set-07 | `aws_kms_key.data` | `data_kms_arn` (있음) |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "trail_kms_arn" { value = aws_kms_key.addon_trail[0].arn }
```

```powershell
terraform output -raw trail_kms_arn
aws cloudtrail describe-trails --trail-name-list (terraform output -raw trail_name) `
  --query "trailList[].KmsKeyId"

# key policy 에 cloudtrail 서비스 문장이 있는지 (없으면 apply 가 실패한다)
aws kms get-key-policy --key-id (terraform output -raw trail_kms_arn) --policy-name default `
  --query Policy --output text | ConvertFrom-Json |
  Select-Object -ExpandProperty Statement | Select-Object Sid, Principal
```

필요한 문장: `cloudtrail.amazonaws.com` 의 `kms:GenerateDataKey*`·`kms:DescribeKey`, CloudWatch Logs를 켰다면 `logs.<region>.amazonaws.com` 도 ([kms](../kms/README.md) 3번).
</details>

## 4. 무결성 검증 (채점 항목일 때)

```powershell
aws cloudtrail validate-logs `
  --trail-arn (terraform output -raw trail_arn) `
  --start-time (Get-Date).AddHours(-2).ToUniversalTime().ToString("s")
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

`enable_log_file_validation = true` 여야 다이제스트 파일이 생긴다. 첫 다이제스트는 **최대 1시간** 뒤다:

```powershell
aws s3 ls "s3://$(terraform output -raw trail_bucket)/AWSLogs/$(terraform output -raw account_id)/CloudTrail-Digest/" --recursive |
  Select-Object -First 3

aws cloudtrail describe-trails --trail-name-list (terraform output -raw trail_name) `
  --query "trailList[].LogFileValidationEnabled"
```

채점이 검증 실행 결과가 아니라 **설정값(`LogFileValidationEnabled`)만 보는 경우가 대부분**이다 — 다이제스트를 기다리느라 시간을 쓰지 않는다.
</details>

## VERIFY

```powershell
$t = terraform output -raw trail_name
aws cloudtrail describe-trails --trail-name-list $t `
  --query "trailList[].[Name,IsMultiRegionTrail,LogFileValidationEnabled,IncludeGlobalServiceEvents,KmsKeyId]"
aws cloudtrail get-trail-status --name $t --query "[IsLogging,LatestDeliveryTime]"
aws cloudtrail get-event-selectors --trail-name $t
```

## TROUBLESHOOT

- 대상 루트에 이미 `aws_cloudtrail` 이나 Trail용 버킷이 있으면 **중복 생성하지 않는다.** 기존 리소스에 `enable_log_file_validation = true`, 멀티 리전·글로벌 이벤트, CW Logs·KMS 참조만 이식한다.
- 기본 `event_selector` 는 **management event만** 수집한다. S3 객체·Lambda 호출 같은 data event 요구면 `advanced_event_selector` 로 확장한다.
- `cloud_watch_logs_group_arn` 은 끝에 `:*` 가 필요하다.
- KMS를 켜면 key policy에 CloudTrail·CloudWatch Logs 서비스 문장이 함께 있어야 한다 — 없으면 apply가 실패한다.
- 로그 버킷 이름은 **전역 유일**이다. `BucketAlreadyExists` 면 접두를 바꾼다.
- 첫 로그 파일까지 최대 15분, 첫 다이제스트까지 최대 1시간이다. 채점은 보통 설정값을 본다.
- S3 버킷 notification은 **버킷당 하나** — 기존 블록을 덮어쓰지 않는다.

## 실전 구현 (참고용)

없음 — 저장소 어느 세트에도 `aws_cloudtrail` 이 없다. 이 KIT이 유일한 재료다.
