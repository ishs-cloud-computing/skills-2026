# CloudFront 강화 부착 KIT

기존 `aws_cloudfront_distribution` 에 표준 로그 · 지역 제한 · 커스텀 에러 페이지 · 추가 동작 · 오리진 검증 헤더를 붙인다.

## 이 KIT이 맞나

- 과제지 기존 CDN 문항 뒤에 **"액세스 로그"·"지리적 제한"·"에러 페이지"·"캐시 동작 추가"** 가 붙었다 → 맞다.
- **Web ACL을 붙여라** → [waf](../waf/README.md) 2번 블록.
- 아래 블록은 전부 배포 **in-place update**다. 단 `origin_id` 변경은 캐시 동작 참조가 깨져 실패한다.

## 세트별 현재 배포 구성

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 배포 리소스 | `aws_cloudfront_distribution.cdn` | `.cdn[0]` (`enable_cdn` count) | `.cdn` |
| S3 오리진 | `var.s3_origin_id`, `origin_path = /${var.object_prefix}` | `"s3-origin"`, `origin_path = /static` | `"s3-origin"` |
| 앱 오리진 | `var.alb_origin_id` (+ `custom_header`) | `"alb-origin"` · `"lambda-origin"` | `"app-origin"` (**VPC Origin**) |
| `price_class` | `PriceClass_All` | `PriceClass_All` | `PriceClass_All` |
| `default_root_object` | `index.html` | `index.html` | `index.html` |
| `web_acl_id` | **없음** | `aws_wafv2_web_acl.wsc2026.arn` | `aws_wafv2_web_acl.unicorn.arn` |
| `restrictions` | 있음 | 있음 | 있음 |
| `logging_config` | **없음** | **없음** | **없음** |
| `custom_error_response` | **없음** | **없음** | **없음** |
| 도메인 output | `cloudfront_domain` | `cloudfront_domain` (count면 null) | `cloudfront_domain` |
| ID·ARN output | **없음** | **없음** | **없음** |

배포 ID는 대부분의 CLI 확인이 요구하므로 먼저 넣는다:

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "cloudfront_id" {
  value = aws_cloudfront_distribution.cdn.id      # set-03 은 aws_cloudfront_distribution.cdn[0].id
}
output "cloudfront_arn" {
  value = aws_cloudfront_distribution.cdn.arn     # set-03 은 ...cdn[0].arn
}
```

```powershell
terraform output -raw cloudfront_domain
terraform output -raw cloudfront_id
```

## 복사할 파일

| 원본 | 대상 | 언제 |
| --- | --- | --- |
| `cloudfront-logs.tf` | `set-XX/task-1/terraform/` | `logging_config` 를 쓸 때만. 로그 버킷 + ownership(BucketOwnerPreferred) + `awslogsdelivery` ACL grant |
| `variables.tf` | `variables-cfh-addon.tf` | `addon_cfh_*` 변수 |

나머지는 전부 기존 배포 리소스 안에 넣는 인자다.

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_cfh_log_bucket_prefix` | `"skills-cf-logs"` | 로그 버킷 접두. 뒤에 `-<account_id>` |
| `addon_cfh_log_prefix` | `"cloudfront/"` | 로그 객체 키 접두. 끝에 `/` 포함 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # 배포가 update in-place 인지 확인 (재생성이면 중단)
terraform apply       # 배포 갱신은 3~5분
```

## 1. 표준 로그 (S3)

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 aws_cloudfront_distribution 리소스 블록 *안에*
logging_config {
  bucket          = aws_s3_bucket.addon_cf_logs.bucket_domain_name   # <버킷>.s3.amazonaws.com 형식
  prefix          = var.addon_cfh_log_prefix
  include_cookies = false
}

# ACL 보다 배포 갱신이 먼저 가면 실패한다
depends_on = [aws_s3_bucket_acl.addon_cf_logs]
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 `logging_config` 가 **없다** — 새로 넣는다. 로그 버킷은 `cloudfront-logs.tf` 가 만든다.

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "cf_log_bucket" { value = aws_s3_bucket.addon_cf_logs.id }
```

```powershell
terraform output -raw cf_log_bucket
aws cloudfront get-distribution-config --id (terraform output -raw cloudfront_id) `
  --query "DistributionConfig.Logging"

# 로그는 요청 후 보통 수 분~1시간, 최대 24h
aws s3 ls "s3://$(terraform output -raw cf_log_bucket)/cloudfront/"
```

**표준 로그 버킷은 ACL이 필수다.** `BucketOwnerEnforced`(2023-04 이후 기본) 버킷에 로그를 보내면 배포 갱신이 `InvalidArgument: ... does not enable ACL access` 로 실패한다. **기존 정적 호스팅 버킷(`s3_bucket_name`)을 로그 대상으로 쓰지 않는다.**

`logging_config.bucket` 은 `bucket_domain_name` 이지 `bucket_regional_domain_name` 이 아니다.
</details>

## 2. 지역 제한

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 aws_cloudfront_distribution 안의 restrictions 블록을 *교체*
restrictions {
  geo_restriction {
    restriction_type = "whitelist"    # blacklist / none
    locations        = ["KR", "US"]   # ISO 3166-1 alpha-2
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**세 세트 모두 `restrictions` 블록이 이미 있다.** 새로 추가하면 `Duplicate block` 이다 — 안의 `restriction_type`·`locations` 만 바꾼다.

```powershell
aws cloudfront get-distribution-config --id (terraform output -raw cloudfront_id) `
  --query "DistributionConfig.Restrictions.GeoRestriction"
```

`geo_restriction` 은 WAF `geo_match` 와 역할이 겹친다. 채점이 어느 쪽을 읽는지 과제지로 확인하고 **한 쪽만** 쓴다 — WAF 쪽이면 [waf-extra-rules](../waf-extra-rules/README.md) 3번이다.
</details>

## 3. 커스텀 에러 응답

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 aws_cloudfront_distribution 리소스 블록 *안에* — 에러 코드마다 블록 하나
custom_error_response {
  error_code            = 403
  response_code         = 404
  response_page_path    = "/error.html"   # 기본 오리진 기준 경로
  error_caching_min_ttl = 10
}
custom_error_response {
  error_code            = 404
  response_code         = 404
  response_page_path    = "/error.html"
  error_caching_min_ttl = 10
}
```

<details><summary><b>값 뽑기 — 세트별 (origin_path 때문에 실제 객체 위치가 다르다)</b></summary>

`response_page_path` 는 **기본 오리진** 기준이다. S3 오리진에 `origin_path` 가 있으면 그 하위에서 찾는다.

| 세트 | S3 `origin_path` | `/error.html` 의 실제 S3 키 |
| --- | --- | --- |
| set-02 | `/${var.object_prefix}` (예: `/web/main`) | `web/main/error.html` |
| set-03 | `/static` | `static/error.html` |
| set-07 | 없음 | `error.html` |

객체를 먼저 올린다 — 없으면 에러 페이지 대신 원래 에러가 나간다:

```powershell
$b = terraform output -raw s3_bucket_name
aws s3 cp .\error.html "s3://$b/static/error.html"     # set-03 기준. 세트별 prefix 로 바꾼다
aws s3 ls "s3://$b/" --recursive | Select-String error.html

aws cloudfront get-distribution-config --id (terraform output -raw cloudfront_id) `
  --query "DistributionConfig.CustomErrorResponses"
```

Terraform으로 올리려면 기존 `aws_s3_object.static` 옆에 한 블록 추가한다:

```hcl
# 파일: set-XX/task-1/terraform/s3.tf
resource "aws_s3_object" "addon_error_page" {
  bucket       = aws_s3_bucket.web.id            # ← 세트별 주소
  key          = "static/error.html"             # ← 세트별 origin_path 와 맞춘다
  source       = "${path.module}/assets/error.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/assets/error.html")
}
```
</details>

## 4. 추가 ordered_cache_behavior

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 ordered_cache_behavior 뒤에 (선언 순서 = 매칭 우선순위)
ordered_cache_behavior {
  path_pattern             = "/health"
  target_origin_id         = "app-origin"          # ← 세트별 origin_id
  viewer_protocol_policy   = "redirect-to-https"
  allowed_methods          = ["GET", "HEAD", "OPTIONS"]
  cached_methods           = ["GET", "HEAD"]
  cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"   # Managed-CachingDisabled
  origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"   # Managed-AllViewerExceptHostHeader
}
```

관리형 정책 ID는 전 계정 공통 고정값이다. `data "aws_cloudfront_cache_policy" { name = "Managed-CachingDisabled" }` 로 이름 조회해도 된다(set-02 패턴).

<details><summary><b>값 뽑기 — 세트별 (origin_id를 틀리면 apply가 실패한다)</b></summary>

| 세트 | 쓸 수 있는 `target_origin_id` |
| --- | --- |
| set-02 | `var.s3_origin_id` · `var.alb_origin_id` — **변수라 리터럴을 적지 않는다** |
| set-03 | `"s3-origin"` · `"alb-origin"` · `"lambda-origin"` |
| set-07 | `"s3-origin"` · `"app-origin"` |

```powershell
# 현재 배포의 origin id 목록을 그대로 확인
aws cloudfront get-distribution-config --id (terraform output -raw cloudfront_id) `
  --query "DistributionConfig.Origins.Items[].Id"

# set-02 는 변수값을 콘솔로
terraform console
> var.alb_origin_id

# 동작 확인 (배포 전파 3~5분 뒤)
$d = terraform output -raw cloudfront_domain
curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/health"
curl.exe -sI "https://$d/health" | Select-String "x-cache"
```
</details>

## 5. 오리진 검증 헤더 (X-Origin-Verify)

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 aws_cloudfront_distribution 의 ALB origin {} 블록 *안에*
custom_header {
  name  = "X-Origin-Verify"
  value = random_password.addon_origin_verify.result
}
```

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
resource "random_password" "addon_origin_verify" {
  length  = 32     # 20자 이상 요구하는 세트가 있다
  special = false
}
```

ALB 쪽이 짝이다 — [alb-hardening](../alb-hardening/README.md) 의 "리스너 기본 403" + `aws_lb_listener_rule.addon_origin_verify`.

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 현재 | 필요 여부 |
| --- | --- | --- |
| set-02 | `custom_header` **이미 있음** (ALB origin + S3 origin 둘 다) | 그대로. 값만 ALB 규칙과 맞춘다 |
| set-03 | ALB origin에 없음 | Ingress + WAF로 대신하는 구성 |
| set-07 | 없음 — **VPC Origin** 이라 헤더 검증이 불필요 | 추가하지 않는다 |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "origin_verify_header" {
  value     = random_password.addon_origin_verify.result
  sensitive = true
}
```

```powershell
$v = terraform output -raw origin_verify_header
$d = terraform output -raw cloudfront_domain

curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/"                                       # 200 (CloudFront 경유)
curl.exe -s -o NUL -w "%{http_code}`n" "http://$(terraform output -raw book_alb_dns)/"     # 403 (ALB 직접)
curl.exe -s -o NUL -w "%{http_code}`n" -H "X-Origin-Verify: $v" "http://$(terraform output -raw book_alb_dns)/health"   # 200
```

같은 값을 두 곳에서 참조해야 불일치가 없다 — `var.addon_albh_header_value = random_password.addon_origin_verify.result` 로 연결하거나 tfvars에 같은 값을 넣는다. **값을 바꾸면 배포 갱신(3~5분) 동안 403이 섞인다.**
</details>

## 6. 기타 한 줄 인자

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 aws_cloudfront_distribution 리소스 블록 *안에*
default_root_object = "index.html"
price_class         = "PriceClass_All"   # _100(북미·유럽) / _200(+아시아) / _All
web_acl_id          = aws_wafv2_web_acl.unicorn.arn   # CLOUDFRONT scope ACL 의 ARN (ID 아님)
http_version        = "http2and3"
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | `price_class` | `default_root_object` | `web_acl_id` |
| --- | --- | --- | --- |
| set-02 | `PriceClass_All` 있음 | `index.html` 있음 | **없음** — [waf](../waf/README.md) 로 만든 뒤 추가 |
| set-03 | 있음 | 있음 | `aws_wafv2_web_acl.wsc2026.arn` 있음 |
| set-07 | 있음 | 있음 | `aws_wafv2_web_acl.unicorn.arn` 있음 |

```powershell
aws cloudfront get-distribution-config --id (terraform output -raw cloudfront_id) `
  --query "DistributionConfig.[DefaultRootObject,PriceClass,WebACLId,HttpVersion]"
```

`price_class` 는 채점 항목으로 자주 나온다 (set-02 "전세계 빠른 접근" → `PriceClass_All`). `web_acl_id` 는 ARN이며 **REGIONAL ACL은 붙지 않는다** — 다른 scope면 `InvalidWebACLId`.
</details>

<details><summary><b>실시간 로그 — task-1 세 세트에는 요구가 없다 (Kinesis 필요)</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
resource "aws_cloudfront_realtime_log_config" "addon" {
  name          = "skills-cf-rt-log"
  sampling_rate = 100
  fields        = ["timestamp", "c-ip", "sc-status", "cs-uri-stem", "cs-user-agent"]

  endpoint {
    stream_type = "Kinesis"
    kinesis_stream_config {
      role_arn   = aws_iam_role.addon_cf_rt.arn      # cloudfront.amazonaws.com 신뢰 + kinesis:PutRecord(s)
      stream_arn = aws_kinesis_stream.addon_cf_rt.arn
    }
  }
}

# default_cache_behavior / ordered_cache_behavior 블록 안에
realtime_log_config_arn = aws_cloudfront_realtime_log_config.addon.arn
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "cf_realtime_log_arn" { value = aws_cloudfront_realtime_log_config.addon.arn }
```

스트림·역할은 이 KIT에 없다 — [kinesis-firehose](../kinesis-firehose/README.md). 과제지가 요구할 때만 만든다 (비용·불필요 리소스 감점).
</details>

## VERIFY

```powershell
$id = terraform output -raw cloudfront_id
aws cloudfront get-distribution-config --id $id `
  --query "DistributionConfig.[Logging,Restrictions,CustomErrorResponses,DefaultRootObject,PriceClass,WebACLId]"
aws cloudfront get-distribution --id $id --query "Distribution.Status"   # Deployed 여야 반영 끝
curl.exe -sI "https://$(terraform output -raw cloudfront_domain)/" | Select-Object -First 12
```

## TROUBLESHOOT

- 위 블록은 전부 배포 **in-place update**. 단 `origin {}` 의 `origin_id` 변경은 캐시 동작 참조가 깨져 실패한다.
- **표준 로그 버킷은 ACL 필수.** 기존 정적 호스팅 버킷을 로그 대상으로 쓰지 않는다. ACL 없이 가려면 표준 로그 v2(`aws_cloudwatch_log_delivery_*`)인데 리소스 3개가 더 든다.
- `logging_config.bucket` 은 `bucket_domain_name` 이다.
- `custom_error_response.response_page_path` 는 **기본 오리진 + origin_path** 기준. 객체가 없으면 원래 에러가 나간다.
- `web_acl_id` 는 wafv2 ARN. REGIONAL ACL은 붙지 않는다.
- 검증 헤더 값을 바꾸면 배포 갱신 동안 403이 섞인다.
- set-03의 배포는 `count` 로 게이트돼 있다 — 참조를 전부 `cdn[0]` 으로 쓰고, `enable_cdn = false` 면 output이 null이 된다.

## 실전 구현 (참고용)

- set-02 task-1 `terraform/cloudfront.tf` · `alb.tf` — 오리진 커스텀 헤더 + ALB 헤더 조건 규칙 + 기본 403
- set-07 task-1 `terraform/cloudfront.tf` — VPC Origin, `/health` ordered behavior, `web_acl_id`
- set-03 task-1 `terraform/cloudfront.tf` — Lambda Function URL 오리진 + OAC + origin request policy
- set-07 task-2 module-2-cdn-function `terraform/cloudfront.tf` — 커스텀 cache policy · response headers policy
- `logging_config` · `custom_error_response` 는 실전 구현이 없다.
