# cloudfront-hardening 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 `aws_cloudfront_distribution` 에 로그·지역 제한·에러 페이지·추가 동작·오리진 검증 헤더를 붙이는 블록 모음.
1과제 Security/Observability 옵션 확장(set-02/08/09 task-1), set-07 m2 CDN 에 대응한다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 0개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_cfh_log_bucket_prefix` | `"skills-cf-logs"` | CloudFront 표준 로그 버킷 이름 접두. 뒤에 -<account_id> 가 붙는다. 과제지 명시 이름이면 그대로 |
| `addon_cfh_log_prefix` | `"cloudfront/"` | 로그 객체 키 접두(logging_config.prefix). 끝에 / 포함 |

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

- `cloudfront-logs.tf` — 표준 로그 대상 S3 버킷 + ownership(BucketOwnerPreferred) + awslogsdelivery ACL grant. `logging_config` 블록을 쓸 때만 복사
- `variables.tf` — `addon_cfh_*` 변수(로그 버킷 접두·키 접두)

나머지는 전부 기존 배포 리소스 안에 넣는 인자라 README 블록으로 충분하다.

## 부착 절차

1. 로그가 필요하면 `cloudfront-logs.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다. 로그 불필요면 tf 복사 없이 아래 블록만 쓴다.
2. 필요한 블록을 기존 `aws_cloudfront_distribution` 리소스 안에 넣는다. 오리진 검증 헤더는 ALB 리스너 규칙이 짝이다 — `shared/addons/alb-hardening/` 의 `aws_lb_listener_rule.addon_origin_verify` 를 같이 붙인다.
3. `terraform.tfvars`:

   ```hcl
   addon_cfh_log_bucket_prefix = "skills-cf-logs"   # 과제지 명시 이름
   addon_cfh_log_prefix        = "cloudfront/"
   ```

4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 배포가 **update in-place** 인지 확인(재생성이면 중단) → `terraform apply`. 배포 갱신은 3~5분.
5. 검증:

   ```powershell
   aws cloudfront get-distribution-config --id <ID> --query 'DistributionConfig.[Logging,Restrictions,CustomErrorResponses,DefaultRootObject,PriceClass,WebACLId]'
   aws s3 ls s3://skills-cf-logs-<ACCOUNT>/cloudfront/     # 로그는 요청 후 최대 24h, 보통 수 분~1h
   ```

## 블록

### 표준 로그 (S3)

```hcl
# aws_cloudfront_distribution 리소스 안에:
logging_config {
  bucket          = aws_s3_bucket.addon_cf_logs.bucket_domain_name   # <버킷>.s3.amazonaws.com 형식
  prefix          = var.addon_cfh_log_prefix
  include_cookies = false
}
```

`depends_on = [aws_s3_bucket_acl.addon_cf_logs]` 를 배포 리소스에 추가한다 — ACL 보다 배포 갱신이 먼저 가면 실패한다.

### 지역 제한

```hcl
# aws_cloudfront_distribution 리소스 안에 (기존 restrictions 블록을 교체):
restrictions {
  geo_restriction {
    restriction_type = "whitelist"   # blacklist / none
    locations        = ["KR", "US"]  # ISO 3166-1 alpha-2
  }
}
```

### 커스텀 에러 응답

```hcl
# aws_cloudfront_distribution 리소스 안에 (에러 코드마다 블록 하나):
custom_error_response {
  error_code            = 403
  response_code         = 404
  response_page_path    = "/error.html"   # 기본 오리진(S3)에 해당 객체가 있어야 한다
  error_caching_min_ttl = 10
}
custom_error_response {
  error_code            = 404
  response_code         = 404
  response_page_path    = "/error.html"
  error_caching_min_ttl = 10
}
```

### 추가 ordered_cache_behavior (예: /health → ALB)

```hcl
# aws_cloudfront_distribution 리소스 안에 (기존 ordered_cache_behavior 뒤, 순서 = 우선순위):
ordered_cache_behavior {
  path_pattern             = "/health"
  target_origin_id         = "<ALB origin_id>"
  viewer_protocol_policy   = "redirect-to-https"
  allowed_methods          = ["GET", "HEAD", "OPTIONS"]
  cached_methods           = ["GET", "HEAD"]
  cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"   # Managed-CachingDisabled
  origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"   # Managed-AllViewerExceptHostHeader
}
```

관리형 정책 ID 는 전 계정 공통 고정값. `data "aws_cloudfront_cache_policy" { name = "Managed-CachingDisabled" }` 로 이름 조회해도 된다(set-02·set-08).

### 오리진 검증 헤더 (X-Origin-Verify) + ALB 리스너 규칙

```hcl
# aws_cloudfront_distribution 의 ALB origin {} 블록 안에:
custom_header {
  name  = "X-Origin-Verify"
  value = random_password.addon_origin_verify.result   # 또는 var 로 고정값
}
```

```hcl
# 새 리소스 (set-08 task-1 패턴 — 20자 이상 요구 대응):
resource "random_password" "addon_origin_verify" {
  length  = 32
  special = false
}
```

ALB 쪽: 리스너 `default_action` 을 403 fixed-response 로 바꾸고 헤더 조건 규칙으로 forward 한다
— `shared/addons/alb-hardening/alb-hardening.tf` 의 `aws_lb_listener_rule.addon_origin_verify` + README "리스너 기본 403" 블록.
같은 값을 두 곳에서 참조해야 불일치가 없다(`var.addon_albh_header_value = random_password.addon_origin_verify.result` 로 연결하거나 tfvars 에 같은 값).

### 기타 한 줄 인자

```hcl
# aws_cloudfront_distribution 리소스 안에:
default_root_object = "index.html"
price_class         = "PriceClass_All"     # PriceClass_100 (북미·유럽) / PriceClass_200 (+아시아) / PriceClass_All
web_acl_id          = aws_wafv2_web_acl.<기존>.arn   # CLOUDFRONT scope ACL 의 ARN (ID 아님)
http_version        = "http2and3"
```

### 실시간 로그 (선택, Kinesis Data Stream 필요)

```hcl
resource "aws_cloudfront_realtime_log_config" "addon" {
  name          = "skills-cf-rt-log"
  sampling_rate = 100
  fields        = ["timestamp", "c-ip", "sc-status", "cs-uri-stem", "cs-user-agent"]

  endpoint {
    stream_type = "Kinesis"
    kinesis_stream_config {
      role_arn   = aws_iam_role.addon_cf_rt.arn      # kinesis:PutRecord(s)·DescribeStream 허용, cloudfront.amazonaws.com 신뢰
      stream_arn = aws_kinesis_stream.addon_cf_rt.arn
    }
  }
}

# default_cache_behavior / ordered_cache_behavior 블록 안에:
realtime_log_config_arn = aws_cloudfront_realtime_log_config.addon.arn
```

스트림·역할은 이 키트에 없다(과제지가 요구할 때만 — 비용·리소스 감점 대상).

## TROUBLESHOOT — 이 KIT 고유 함정
- 위 블록은 전부 배포 **in-place update**. 재생성 유발 인자 없음. 단 `origin {}` 의 `origin_id` 변경은 캐시 동작 참조가 깨져 실패한다.
- **표준 로그 버킷은 ACL 필수**: `BucketOwnerEnforced`(2023-04 이후 기본) 버킷에 로그를 보내면 배포 갱신이 `InvalidArgument: The S3 bucket that you specified for CloudFront logs does not enable ACL access` 로 실패한다. 기존 정적 호스팅 버킷을 로그 대상으로 쓰지 말고 `cloudfront-logs.tf` 버킷을 쓴다. ACL 없이 가려면 표준 로그 v2(`aws_cloudwatch_log_delivery_source/destination/delivery`, 확인 필요)인데 리소스 3개가 더 든다.
- 로그 버킷은 us-east-1 제약 없음(일부 opt-in 리전 제외). `logging_config.bucket` 은 `bucket_domain_name`(`<버킷>.s3.amazonaws.com`)이지 `bucket_regional_domain_name` 이 아니다.
- `geo_restriction` 은 WAF `geo_match` 와 역할이 겹친다. 채점이 `get-distribution-config` 의 `Restrictions` 를 보는지 WAF 룰을 보는지 과제지로 확인.
- `custom_error_response.response_page_path` 는 **기본 오리진** 기준 경로. S3 오리진에 `origin_path` 가 있으면(set-02 `/web/main`) 그 하위에서 찾는다. 객체가 없으면 에러 페이지 대신 원래 에러가 나간다.
- `web_acl_id` 는 ARN(wafv2). 배포와 Web ACL 이 다른 scope/리전이면 apply 에서 `InvalidWebACLId`. REGIONAL ACL 은 붙지 않는다.
- `price_class` 는 채점 항목으로 자주 나온다(set-02 "전세계 빠른 접근" → `PriceClass_All`). 기본값은 `PriceClass_All`.
- 검증 헤더 값을 바꾸면 배포 갱신(3~5분) 동안 구·신 값이 섞여 ALB 가 403 을 낸다. 값은 처음에 확정하고 바꾸지 않는다.
- `mark.sh` 가 `Comment` 또는 `Name` 태그로 배포를 식별하는 세트가 있다(set-02·set-07 m2·set-08) — 건드리지 않는다.

## 실전 구현 (참고용)

- set-02 task-1 `terraform/cloudfront.tf`·`alb.tf` — 오리진 커스텀 헤더 + ALB 헤더 조건 규칙 + 기본 403, PriceClass_All, default_root_object
- set-08 task-1 `terraform/cloudfront.tf`·`alb.tf` — random_password 로 헤더 값 생성, /v1/* ordered behavior
- set-07 task-1 `terraform/cloudfront.tf` — VPC Origin, /health ordered behavior, web_acl_id
- set-07 task-2 module-2-cdn-function `terraform/cloudfront.tf` — 커스텀 cache policy·response headers policy
- `logging_config`·`custom_error_response`·`geo_restriction` 실전 구현은 없음
