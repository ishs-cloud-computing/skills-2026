# S3 강화 부착 KIT

기존 버킷에 버전 관리 · 수명주기 · 서버 액세스 로그 · EventBridge 알림 · OAC 정책 · Object Lock을 붙인다.

## 이 KIT이 맞나

- 과제지 기존 S3 문항 뒤에 **"버저닝"·"수명주기"·"액세스 로그"·"Object Lock"·"퍼블릭 차단"** 이 붙었다 → 맞다.
- **CMK로 암호화**만 요구 → [kms](../kms/README.md) 1번 블록.
- versioning·lifecycle·logging·notification·정책은 전부 **별도 리소스 = in-place**. 기존 `aws_s3_bucket` 재생성이 없다. `object_lock_enabled` 만 재생성이다.

## 세트별 대상 버킷

| 세트 | 버킷 리소스 | 이름 output | 기존 정책 | 이미 있는 것 |
| --- | --- | --- | --- | --- |
| set-02 | `aws_s3_bucket.web` | `s3_bucket_name` | `aws_s3_bucket_policy.web` (OAC) | SSE-KMS · public access block |
| set-03 | `aws_s3_bucket.static` | `s3_bucket_name` | `aws_s3_bucket_policy.static` (OAC, `enable_cdn` count 게이트) | SSE-KMS · public access block |
| set-07 | `aws_s3_bucket.web` | `s3_bucket_name` | `aws_s3_bucket_policy.web` (OAC) | SSE-KMS · public access block · **`aws_s3_bucket_versioning.web`** |

세 세트 모두 `s3_bucket_name` output이 이미 있다:

```powershell
terraform output -raw s3_bucket_name
```

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `s3-hardening.tf` | `set-XX/task-1/terraform/` | versioning · lifecycle(map 변수) · 로그 버킷 + 정책 + logging · notification(eventbridge) |
| `variables.tf` | `variables-s3h-addon.tf` | `addon_s3h_*` 변수 |

**과제지가 요구하지 않는 리소스 블록은 지운다** (불필요 리소스 감점). 기존 파일에 이미 있는 항목(set-07 versioning)도 지운다 — 같은 버킷에 같은 설정 리소스 둘은 state가 어긋난다.

## CHANGE — 당일 고치는 값

`terraform.tfvars`. 필수 없음(기본값으로 apply된다).

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_s3h_bucket_name` | `"skills-static-bucket"` | 보강 대상 버킷 이름. **이름이 계정 ID 접미인 세트가 많으니 `aws_s3_bucket.<기존>.id` 직접 참조가 안전하다** |
| `addon_s3h_lifecycle_rules` | map | key = 규칙 id. prefix 빈 문자열 = 전체, 0 = 해당 동작 없음 |
| `addon_s3h_log_bucket_prefix` | `"skills-s3-access-logs"` | 액세스 로그 대상 버킷 접두 (뒤에 `-<account_id>`) |
| `addon_s3h_log_prefix` | `"s3/"` | 로그 객체 키 접두 (끝에 `/` 포함) |

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_s3h_bucket_name = "skills-static-123456789012"
addon_s3h_lifecycle_rules = {
  logs   = { prefix = "logs/", transition_days = 30, transition_storage_class = "STANDARD_IA", expiration_days = 90, noncurrent_days = 30 }
  static = { prefix = "static/", noncurrent_days = 7 }
  # all  = { expiration_days = 365 }      # prefix 생략 = 전체 객체
}
addon_s3h_log_bucket_prefix = "skills-s3-access-logs"
addon_s3h_log_prefix        = "s3/"
```

<details><summary><b>값 뽑기 — 세트별 (tfvars 대신 직접 참조가 안전)</b></summary>

`var.addon_s3h_bucket_name` 을 아래로 치환한다 (로그 정책의 `arn:aws:s3:::${...}` 도 `.arn` 으로):

| 세트 | 치환값 |
| --- | --- |
| set-02 | `aws_s3_bucket.web.id` / `aws_s3_bucket.web.arn` |
| set-03 | `aws_s3_bucket.static.id` / `aws_s3_bucket.static.arn` |
| set-07 | `aws_s3_bucket.web.id` / `aws_s3_bucket.web.arn` |

또는 실제 이름을 뽑아 tfvars에 박는다:

```powershell
terraform output -raw s3_bucket_name
terraform output -raw account_id      # 세 세트 모두 있음
```
</details>

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # 기존 aws_s3_bucket 에 diff 가 없어야 한다
terraform apply
```

## FAST — terraform 없이 CLI 로 붙이기

채점은 **관찰 가능한 상태**만 본다. 버킷 속성은 전부 in-place 라 파일 복사·`apply` 없이 끝난다.

**대가**: terraform state 와 실물이 어긋난다. 이 세트에 이후 `apply` 를 걸면 되돌아가므로,
CLI 로 붙였으면 그 세트는 더 apply 하지 않거나 나중에 같은 값을 `.tf` 에도 넣는다.

```powershell
$B = '<버킷>'

aws s3api put-bucket-versioning --bucket $B --versioning-configuration Status=Enabled

aws s3api put-public-access-block --bucket $B `
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# EventBridge 알림
aws s3api put-bucket-notification-configuration --bucket $B `
  --notification-configuration file://notif.json
```

JSON 을 받는 인자는 **shorthand 로 못 넣는다.** 파일로 만들어 `file://` 로 넘긴다 —
PowerShell 에서 인라인 JSON 은 따옴표가 깨진다.

```powershell
@'
{"Rules":[{"ID":"expire","Status":"Enabled","Filter":{"Prefix":""},
  "Expiration":{"Days":30},
  "NoncurrentVersionExpiration":{"NoncurrentDays":7}}]}
'@ | Set-Content -Encoding utf8 lifecycle.json
aws s3api put-bucket-lifecycle-configuration --bucket $B --lifecycle-configuration file://lifecycle.json

@'
{"LoggingEnabled":{"TargetBucket":"<로그버킷>","TargetPrefix":"<프리픽스>/"}}
'@ | Set-Content -Encoding utf8 logging.json
aws s3api put-bucket-logging --bucket $B --bucket-logging-status file://logging.json

@'
{"EventBridgeConfiguration":{}}
'@ | Set-Content -Encoding utf8 notif.json
```

- **버킷 정책**(OAC 한정 등)은 버킷당 하나뿐이다. `get-bucket-policy` 로 기존 것을 먼저 받아 statement 를 **추가**한다. 덮어쓰면 CloudFront 가 403 이 된다.
- **Object Lock 은 생성 시에만** 켤 수 있다. CLI 로도 안 된다 → 아래 [7. Object Lock](#7-object-lock-생성-시에만) 참조.

## 1. 버전 관리

```hcl
# 파일: set-XX/task-1/terraform/s3-hardening.tf   (KIT에서 복사됨)
resource "aws_s3_bucket_versioning" "addon" {
  bucket = aws_s3_bucket.web.id     # ← 세트별 주소로 치환
  versioning_configuration {
    status = "Enabled"
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**set-07에는 `aws_s3_bucket_versioning.web` 이 이미 있다.** 중복 선언하지 말고 기존 것을 쓴다.

```powershell
Select-String -Path s3.tf -Pattern "aws_s3_bucket_versioning"     # 먼저 확인
$b = terraform output -raw s3_bucket_name
aws s3api get-bucket-versioning --bucket $b
```

**버전 관리는 켜면 못 끈다** (Suspended만 가능). teardown 대비로 기존 버킷 리소스에 `force_destroy = true` 를 같이 넣는다 (in-place):

```hcl
# 파일: set-XX/task-1/terraform/s3.tf  — 기존 aws_s3_bucket 블록 안에
force_destroy = true
```
</details>

## 2. 수명주기

```hcl
# 파일: set-XX/task-1/terraform/s3-hardening.tf
resource "aws_s3_bucket_lifecycle_configuration" "addon" {
  bucket = aws_s3_bucket.web.id     # ← 세트별 주소로 치환

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {
      prefix = "logs/"
    }
    transition {
      days          = 30            # STANDARD_IA/ONEZONE_IA 는 최소 30. 즉시 전환이면 GLACIER_IR
      storage_class = "STANDARD_IA"
    }
    expiration {
      days = 90                     # transition.days 보다 커야 한다
    }
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 수명주기 구성이 **없다** — 새로 만든다.

```powershell
$b = terraform output -raw s3_bucket_name
aws s3api get-bucket-lifecycle-configuration --bucket $b
```

규칙은 하루 한 번(UTC 00:00 부근) 평가된다 — **채점 시 실제 전환/만료는 안 보이고 설정값만 본다.**
</details>

## 3. 서버 액세스 로그

```hcl
# 파일: set-XX/task-1/terraform/s3-hardening.tf   (KIT에서 복사됨)
resource "aws_s3_bucket_logging" "addon" {
  bucket        = aws_s3_bucket.web.id            # ← 세트별 주소
  target_bucket = aws_s3_bucket.addon_s3h_logs.id # 별도 버킷 — 원본과 같으면 무한 로그
  target_prefix = var.addon_s3h_log_prefix
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

로그 대상 버킷은 KIT이 새로 만든다. 이름을 output으로 노출한다:

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "s3_access_log_bucket" { value = aws_s3_bucket.addon_s3h_logs.id }
```

```powershell
terraform output -raw s3_access_log_bucket
aws s3api get-bucket-logging --bucket (terraform output -raw s3_bucket_name)
aws s3 ls "s3://$(terraform output -raw s3_access_log_bucket)/s3/" --recursive | Select-Object -First 5
```

대상 버킷은 **같은 리전·같은 계정**, 원본과 다른 버킷이어야 한다. `BucketOwnerEnforced`(기본)면 ACL이 아니라 **버킷 정책**으로 `logging.s3.amazonaws.com` 에 PutObject를 준다(KIT 파일에 포함). 로그는 수 시간 지연되므로 채점은 설정값으로 본다.
</details>

## 4. CloudFront OAC 버킷 정책 (배포 ARN 한정)

```hcl
# 파일: set-XX/task-1/terraform/s3.tf
# 기존 aws_s3_bucket_policy 가 있으면 새로 만들지 말고 그 document 에 statement 만 추가한다
data "aws_iam_policy_document" "addon_s3_oac" {
  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]     # ← 세트별 주소
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]   # ← 세트별 주소
    }
  }
}

resource "aws_s3_bucket_policy" "addon_s3_oac" {
  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.addon_s3_oac.json
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**세 세트 모두 OAC 정책이 이미 있다.** 새 `aws_s3_bucket_policy` 를 또 만들면 마지막 apply가 이겨서 기존 정책이 날아간다 — 기존 document에 statement만 추가한다.

| 세트 | 기존 정책 | 배포 ARN 참조 |
| --- | --- | --- |
| set-02 | `aws_s3_bucket_policy.web` | `aws_cloudfront_distribution.cdn.arn` |
| set-03 | `aws_s3_bucket_policy.static` | `aws_cloudfront_distribution.cdn[0].arn` — 정책도 **같은 count 로 게이트** |
| set-07 | `aws_s3_bucket_policy.web` | `aws_cloudfront_distribution.cdn.arn` |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "cloudfront_arn" {
  value = aws_cloudfront_distribution.cdn.arn      # set-03 은 cdn[0].arn
}
```

```powershell
terraform output -raw cloudfront_arn
terraform output -raw cloudfront_domain          # 세 세트 모두 이미 있음
aws s3api get-bucket-policy --bucket (terraform output -raw s3_bucket_name) --query Policy --output text
```
</details>

## 5. EventBridge 알림

```hcl
# 파일: set-XX/task-1/terraform/s3-hardening.tf
resource "aws_s3_bucket_notification" "addon" {
  bucket      = aws_s3_bucket.web.id
  eventbridge = true
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

`aws_s3_bucket_notification` 은 **버킷당 하나**(PUT으로 전체 교체). 이미 Lambda 트리거가 있으면 새 리소스를 만들지 말고 기존 것에 한 줄 추가한다:

```hcl
# 기존 aws_s3_bucket_notification 블록 안에 (lambda_function {} 등과 공존 가능)
eventbridge = true
```

task-1 세 세트에는 notification 리소스가 **없다** — 새로 만들어도 충돌하지 않는다. (set-02 task-2 module-1-workflow에는 Lambda 트리거가 있다.)

```powershell
aws s3api get-bucket-notification-configuration --bucket (terraform output -raw s3_bucket_name)
# → {"EventBridgeConfiguration": {}}
```
</details>

## 6. 버킷 키 (SSE-KMS 비용 절감)

```hcl
# 파일: set-XX/task-1/terraform/s3.tf
# 기존 aws_s3_bucket_server_side_encryption_configuration 의 rule {} 안에 (in-place)
bucket_key_enabled = true
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 SSE 설정 리소스가 있고 `bucket_key_enabled` 도 **이미 켜져 있다.** 확인만 한다:

```powershell
aws s3api get-bucket-encryption --bucket (terraform output -raw s3_bucket_name) `
  --query "ServerSideEncryptionConfiguration.Rules[].BucketKeyEnabled"
```
</details>

## 7. Object Lock (**생성 시에만**)

```hcl
# 파일: set-XX/task-1/terraform/s3.tf
# 기존 aws_s3_bucket 블록 안에 — 기존 버킷엔 못 켠다(재생성)
object_lock_enabled = true
```

```hcl
# 파일: set-XX/task-1/terraform/s3-hardening.tf   (버전 관리가 먼저 켜져 있어야 한다)
resource "aws_s3_bucket_object_lock_configuration" "addon" {
  bucket = aws_s3_bucket.web.id

  rule {
    default_retention {
      mode = "GOVERNANCE"   # COMPLIANCE 는 root 도 못 지운다 — teardown 불가
      days = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.addon]
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 버킷이 **이미 만들어져 있다.** Object Lock을 켜려면 버킷 재생성 = 정적 자산(`aws_s3_object.static`)·OAC 정책·CloudFront origin이 전부 흔들린다. 배점부터 확인하고 결정한다.

```powershell
aws s3api get-object-lock-configuration --bucket (terraform output -raw s3_bucket_name)
```
</details>

## VERIFY

```powershell
$b = terraform output -raw s3_bucket_name
aws s3api get-bucket-versioning --bucket $b
aws s3api get-bucket-lifecycle-configuration --bucket $b
aws s3api get-bucket-logging --bucket $b
aws s3api get-bucket-notification-configuration --bucket $b
aws s3api get-bucket-encryption --bucket $b
aws s3api get-public-access-block --bucket $b
```

## TROUBLESHOOT

- **버전 관리는 켜면 못 끈다.** teardown 시 `force_destroy = true` 가 없으면 버전 객체 때문에 삭제가 실패한다.
- 수명주기 `transition` 은 **STANDARD_IA·ONEZONE_IA 최소 30일**. 0~29면 apply가 `InvalidArgument` 로 실패한다. 즉시 전환은 `GLACIER_IR`. `expiration.days > transition.days`.
- provider 6.x의 `rule.filter` 는 빈 블록(`filter {}`) 또는 `prefix`/`tag`/`and`/`object_size_*` 중 하나. `prefix` 최상위 인자(구형)는 쓰지 않는다.
- 액세스 로그 대상 버킷을 원본과 같게 두면 **무한 로그**. 대상 버킷에 SSE-KMS 기본 암호화는 지원 안 된다(SSE-S3만).
- `aws_s3_bucket_notification` · `aws_s3_bucket_policy` 는 **버킷당 하나.** 둘을 선언하면 마지막 apply가 이긴다.
- OAC 정책의 `AWS:SourceArn` 은 배포 ARN 정확 일치. set-03처럼 `count` 로 게이트된 배포면 정책도 같은 count로 게이트한다.
- 버킷 이름이 `<ACCOUNT_ID>` 접미인 세트가 많다 — tfvars에 손으로 적지 말고 `aws_s3_bucket.<기존>.id` 를 직접 참조한다.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/s3.tf` — versioning + SSE-KMS(bucket_key) + OAC 정책
- set-02 / set-03 task-1 `terraform/s3.tf` — OAC 정책 (set-03은 count 게이트)
- set-05 task-1 `terraform/s3.tf` — versioning + 객체 단위 SSE-KMS
- set-02 task-2 module-1-workflow `terraform/s3.tf` — `aws_s3_bucket_notification` (Lambda 트리거, prefix/suffix 필터)
- lifecycle · logging · eventbridge · Object Lock은 실전 구현이 없다 — 이 KIT이 처음이다.

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
