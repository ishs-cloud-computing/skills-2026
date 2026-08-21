# s3-hardening 부착 스니펫

기존 S3 버킷에 버전 관리·수명주기·서버 액세스 로그·EventBridge 알림·OAC 정책·Object Lock 을 붙이는 키트.
1과제 Static hosting 버킷 보강(전 세트 task-1), set-02 m1/m4 S3 모듈에 대응한다.

## 파일

- `s3-hardening.tf` — `aws_s3_bucket_versioning` · `aws_s3_bucket_lifecycle_configuration`(map 변수, prefix 별 전환·만료) · 로그 버킷 + `logging.s3.amazonaws.com` 정책 + `aws_s3_bucket_logging` · `aws_s3_bucket_notification.eventbridge`. 전부 기존 버킷 이름을 변수로 받는 별도 리소스
- `variables.tf` — `addon_s3h_*` 변수

`bucket_key_enabled`·OAC 버킷 정책·Object Lock 은 README 블록.

## 부착 절차

1. `s3-hardening.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다. **과제지가 요구하지 않는 리소스 블록은 지운다**(불필요 리소스 감점). 기존 파일에 이미 있는 항목(set-05/07 task-1 은 versioning 있음)도 지운다 — 같은 버킷에 같은 설정 리소스 둘은 충돌하진 않지만 state 가 어긋난다.
2. `terraform.tfvars`. 기존 버킷을 직접 참조하려면 `var.addon_s3h_bucket_name` 을 `aws_s3_bucket.<기존>.id` 로 바꾼다(로그 정책의 `arn:aws:s3:::${...}` 도 `aws_s3_bucket.<기존>.arn` 으로).

   ```hcl
   addon_s3h_bucket_name       = "skills-static-123456789012"
   addon_s3h_lifecycle_rules = {
     logs   = { prefix = "logs/", transition_days = 30, transition_storage_class = "STANDARD_IA", expiration_days = 90, noncurrent_days = 30 }
     static = { prefix = "static/", noncurrent_days = 7 }
     # all  = { expiration_days = 365 }      # prefix 생략 = 전체 객체
   }
   addon_s3h_log_bucket_prefix = "skills-s3-access-logs"
   addon_s3h_log_prefix        = "s3/"
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 `aws_s3_bucket` 에 diff 없음 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws s3api get-bucket-versioning --bucket skills-static-<ACCOUNT>
   aws s3api get-bucket-lifecycle-configuration --bucket skills-static-<ACCOUNT>
   aws s3api get-bucket-logging --bucket skills-static-<ACCOUNT>
   aws s3api get-bucket-notification-configuration --bucket skills-static-<ACCOUNT>   # {"EventBridgeConfiguration": {}}
   aws s3api get-bucket-encryption --bucket skills-static-<ACCOUNT>                   # BucketKeyEnabled
   ```

## 블록

### 버킷 키 (SSE-KMS 비용 절감)

```hcl
# aws_s3_bucket_server_side_encryption_configuration 의 rule {} 안에:
bucket_key_enabled = true
```

### CloudFront OAC 버킷 정책 (배포 ARN 한정)

```hcl
data "aws_iam_policy_document" "addon_s3_oac" {
  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.addon_s3h_bucket_name}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.<기존>.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "addon_s3_oac" {
  bucket = var.addon_s3h_bucket_name
  policy = data.aws_iam_policy_document.addon_s3_oac.json
}
```

버킷 정책도 버킷당 하나 — 기존 `aws_s3_bucket_policy` 가 있으면 그 document 에 statement 만 추가한다.

### 기존 notification 에 EventBridge 추가

```hcl
# 기존 aws_s3_bucket_notification 리소스 안에 (lambda_function {} 등과 공존 가능):
eventbridge = true
```

### 수명주기 단일 규칙 (변수 없이)

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "addon" {
  bucket = var.addon_s3h_bucket_name

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {
      prefix = "logs/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"   # STANDARD_IA 는 최소 30일, GLACIER_IR/GLACIER/DEEP_ARCHIVE 는 0일부터
    }
    expiration {
      days = 90
    }
  }
}
```

### Object Lock (⚠ 생성 시에만)

```hcl
# aws_s3_bucket 리소스 안에 — 기존 버킷엔 못 켠다(재생성):
object_lock_enabled = true

# 새 리소스 (버전 관리 필수):
resource "aws_s3_bucket_object_lock_configuration" "addon" {
  bucket = var.addon_s3h_bucket_name

  rule {
    default_retention {
      mode = "GOVERNANCE"   # COMPLIANCE 는 root 도 못 지운다 — teardown 불가
      days = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.addon]
}
```

## 함정

- versioning·lifecycle·logging·notification·정책은 전부 **별도 리소스 = in-place**. 기존 `aws_s3_bucket` 재생성 없음. `object_lock_enabled` 만 ⚠ 재생성(기존 버킷은 AWS Support 요청 없이는 불가).
- **버전 관리는 켜면 못 끈다**(Suspended 만 가능). teardown 시 `force_destroy = true` 가 없으면 버전 객체 때문에 삭제 실패 → 기존 버킷 리소스에 `force_destroy = true` 를 같이 넣는다(in-place).
- 수명주기 `transition` 은 **STANDARD_IA·ONEZONE_IA 최소 30일**. 0~29 로 쓰면 apply 가 `InvalidArgument` 로 실패. 즉시 전환 요구면 `GLACIER_IR`. `expiration.days` 는 `transition.days` 보다 커야 한다.
- 수명주기 규칙은 하루 한 번(UTC 00:00 부근) 평가 — 채점 시 실제 전환/만료는 안 보이고 설정값만 본다.
- provider 6.x 의 `rule.filter` 는 빈 블록(`filter {}`) 또는 `prefix`/`tag`/`and`/`object_size_*` 중 하나. 스니펫은 prefix 빈 문자열이면 `filter {}` 로 간다. `prefix` 최상위 인자(구형)는 쓰지 않는다.
- 서버 액세스 로그: 대상 버킷은 **같은 리전·같은 계정**, 원본과 다른 버킷. 대상 버킷이 `BucketOwnerEnforced`(기본) 면 ACL 이 아니라 **버킷 정책**으로 `logging.s3.amazonaws.com` 에 PutObject 를 준다(스니펫). `aws:SourceArn` 은 원본 버킷 ARN. 로그는 수 시간 지연 — 채점은 `get-bucket-logging` 설정값으로 본다.
- 로그 대상 버킷을 원본 버킷으로 두면 무한 로그. 대상 버킷에 SSE-KMS 기본 암호화는 지원 안 됨(SSE-S3 만).
- `aws_s3_bucket_notification` 은 **버킷당 하나**(PUT 으로 전체 교체). set-02 m1 처럼 Lambda 트리거가 이미 있으면 그 리소스에 `eventbridge = true` 만 추가 — 새 리소스를 또 만들면 서로 덮어쓴다.
- 버킷 정책도 버킷당 하나. `aws_s3_bucket_policy` 가 둘이면 마지막 apply 가 이긴다.
- `bucket_key_enabled` 는 기존 SSE 설정 리소스 안에 넣는다(in-place). 이미 전 세트에 켜져 있다.
- OAC 정책 `AWS:SourceArn` 은 배포 ARN 정확 일치. 배포가 2차 apply 로 게이트되는 세트(set-03 `enable_cdn`)는 정책도 같은 count 로 게이트.
- 이름이 `<ACCOUNT_ID>`·`<비번호>` 접미인 세트가 많다 — `addon_s3h_bucket_name` 은 tfvars 가 아니라 기존 `local.bucket_name` 직접 참조가 안전하다.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/s3.tf` — versioning + SSE-KMS(bucket_key) + OAC 정책
- set-05 task-1 `terraform/s3.tf` — versioning + 객체 단위 SSE-KMS
- set-02 task-1 `terraform/s3.tf`, set-03 task-1 `terraform/s3.tf` — OAC 정책(배포 ARN 조건, set-03 은 count 게이트)
- set-02 task-2 module-1-workflow `terraform/s3.tf` — `aws_s3_bucket_notification` (Lambda 트리거, prefix/suffix 필터)
- lifecycle·logging·eventbridge·Object Lock 실전 구현은 없음
