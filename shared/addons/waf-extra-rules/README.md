# WAF 룰 추가 부착 KIT

**기존** Web ACL에 `rule {}` 블록을 추가하는 템플릿 모음. Web ACL 자체를 새로 만드는 건 [waf](../waf/README.md).

## 이 KIT이 맞나

- 과제지 기존 WAF 문항 뒤에 **"관리형 룰 그룹"·"Rate limit"·"Geo 차단"·"UA 차단"·"로깅"** 이 붙었다 → 맞다.
- **Web ACL 자체가 없다**(set-02) → [waf](../waf/README.md) 로 먼저 만든다.
- 룰 추가·수정은 Web ACL **in-place update**다. 단 `name`·`scope` 변경은 재생성이고 연결도 끊긴다.

## 세트별 현재 Web ACL

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| Web ACL | **없음** | `aws_wafv2_web_acl.wsc2026` | `aws_wafv2_web_acl.unicorn` |
| 이름 | — | `${var.name_prefix}-waf` | `"unicorn-waf"` (하드코딩) |
| scope | — | `CLOUDFRONT` (`provider = aws.use1`) | `CLOUDFRONT` (`provider = aws.use1`) |
| 파일 | — | `waf.tf` | `waf.tf` |
| 기존 룰 (priority) | — | `-sqli`(1) · `-xss`(2) · `-rate-limit`(3, limit **200**/60s) | `AWSManagedRulesCommonRuleSet`(1) · `KnownBadInputsRuleSet`(2) · `unicorn-rate-limit`(3, limit **50**/60s) |
| `custom_response_body` | — | 없음 | `key = "unicorn-blocked"` |
| 로깅 | — | 없음 | 로그 그룹 `aws-waf-logs-unicorn` + 리소스 정책 + logging_configuration |
| 연결 | — | `aws_cloudfront_distribution.cdn[0].web_acl_id` | `aws_cloudfront_distribution.cdn.web_acl_id` |

**두 세트 모두 CLOUDFRONT scope다.** 새 룰·regex set에도 `provider = aws.use1` 를 붙이고 확인 명령에 `--region us-east-1` 을 붙인다.

```hcl
# 파일: set-03/task-1/terraform/outputs.tf
output "waf_arn"  { value = aws_wafv2_web_acl.wsc2026.arn }
output "waf_id"   { value = aws_wafv2_web_acl.wsc2026.id }
output "waf_name" { value = aws_wafv2_web_acl.wsc2026.name }

# 파일: set-07/task-1/terraform/outputs.tf  (.unicorn 으로)
```

```powershell
# 새 룰의 priority 를 정하기 전에 기존 목록을 본다 (ACL 안에서 유일해야 한다)
$n = terraform output -raw waf_name; $i = terraform output -raw waf_id
aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name $n --id $i `
  --query "WebACL.Rules[].[Priority,Name]" --output table
```

## 복사할 파일

| 원본 | 대상 | 언제 |
| --- | --- | --- |
| `rules.tf` 의 룰 블록만 | 기존 `waf.tf` 안으로 | **기존 ACL이 있으면** — 이 파일의 예시 ACL은 쓰지 않는다 |
| `rules.tf` 통째로 | `set-XX/task-1/terraform/` | Web ACL이 없을 때(set-02). `locals.addon_wafx_enable` 에서 필요한 룰만 `true` |
| `variables.tf` | `variables-wafx-addon.tf` | `addon_wafx_*` 변수 |

regex pattern set을 쓰는 룰이면 `aws_wafv2_regex_pattern_set` 리소스와 해당 변수도 같이 복사한다.

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_wafx_name` | `"skills-waf"` | 룰을 붙일 Web ACL 이름. regex set·metric 이름 접두 |
| `addon_wafx_scope` | `"REGIONAL"` | **set-03/set-07은 `CLOUDFRONT`** — 리소스 전부에 `provider = aws.use1` |
| `addon_wafx_block_body` | `"Request blocked by WAF"` | 차단 응답 본문. 과제지 지정 문자열 그대로 |
| `addon_wafx_common_count_rules` | `["SizeRestrictions_BODY"]` | COUNT로 강등할 하위 룰 이름 |
| `addon_wafx_api_path_regexes` | `["^/v1/.*$", "^/health$"]` | 검사 대상 경로 regex. 여기 없는 경로는 판정하지 않는다 |
| `addon_wafx_rate_limit` | `100` | rate 임계. **최소 10** |
| `addon_wafx_rate_window_sec` | `60` | **60/120/300/600만 허용** |
| `addon_wafx_rate_path_regex` | `"^/v1/.*$"` | rate scope_down 경로. 빈 문자열이면 전 경로 |
| `addon_wafx_geo_country_codes` | `["CN", "RU"]` | 차단할 ISO 3166-1 alpha-2 |
| `addon_wafx_post_body_strings` | `["admin", "sysop"]` | POST body 포함 시 차단 (LOWERCASE 후 CONTAINS) |
| `addon_wafx_header_name` / `_value` | `"x-api-key"` / `"changeme"` | 헤더 조건 룰. 이름은 **소문자** |
| `addon_wafx_ua_regexes` | 스캐너 4종 | 차단할 UA regex |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # Web ACL 이 update in-place 인지 확인
terraform apply
```

## 1. 관리형 룰 그룹 (SQLi / IP 평판 / Common + COUNT 강등)

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# 기존 aws_wafv2_web_acl 리소스 블록 *안에*
rule {
  name     = "sqli"
  priority = 10                     # 기존 룰과 겹치면 바꾼다
  override_action {
    none {}
  }
  statement {
    managed_rule_group_statement {
      vendor_name = "AWS"
      name        = "AWSManagedRulesSQLiRuleSet"
      # 다른 후보: AWSManagedRulesAmazonIpReputationList / AWSManagedRulesCommonRuleSet
      #            AWSManagedRulesKnownBadInputsRuleSet

      # 경로 한정 — managed rule group 은 and_statement 로 감쌀 수 없다
      scope_down_statement {
        regex_pattern_set_reference_statement {
          arn = aws_wafv2_regex_pattern_set.addon_api_paths.arn
          field_to_match {
            uri_path {}
          }
          text_transformation {
            priority = 0
            type     = "URL_DECODE"
          }
          text_transformation {
            priority = 1
            type     = "NORMALIZE_PATH"
          }
        }
      }

      # 오탐 방지 — 특정 하위 룰만 COUNT 로 강등
      rule_action_override {
        name = "SizeRestrictions_BODY"
        action_to_use {
          count {}
        }
      }
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "sqli"
    sampled_requests_enabled   = true
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 이미 있는 관리형 룰 | 새 룰 priority |
| --- | --- | --- |
| set-02 | 없음 (ACL 자체가 없음) | [waf](../waf/README.md) 로 ACL 먼저 |
| set-03 | 없음 — 커스텀 sqli/xss만 | `10` 이상 (기존 1·2·3) |
| set-07 | `AWSManagedRulesCommonRuleSet`(1) · `KnownBadInputs`(2) | `10` 이상. **CommonRuleSet에 `rule_action_override` 가 dynamic 으로 이미 걸려 있다** — 중복 선언 말고 변수 목록에 이름만 추가 |

```powershell
$n = terraform output -raw waf_name; $i = terraform output -raw waf_id
aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name $n --id $i `
  --query "WebACL.Rules[].[Priority,Name,Statement.ManagedRuleGroupStatement.Name]" --output table

$d = terraform output -raw cloudfront_domain
curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/v1/x?id=1' OR 1=1--"    # 403
```

`AWSManagedRulesCommonRuleSet` 은 body 8KB 초과·UA 없음 등으로 정상 트래픽을 막는다. **채점 curl이 UA 없이 오면 `NoUserAgent_HEADER` 를 COUNT로 강등한다.**
</details>

## 2. rate-based + 경로 scope-down + 403 custom body

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# custom_response_body 는 rule 밖, aws_wafv2_web_acl 최상위
custom_response_body {
  key          = "addon-blocked"
  content      = var.addon_wafx_block_body
  content_type = "TEXT_PLAIN"      # TEXT_HTML / APPLICATION_JSON
}

rule {
  name     = "rate-limit"
  priority = 40
  action {
    block {
      custom_response {
        response_code            = 403
        custom_response_body_key = "addon-blocked"
      }
    }
  }
  statement {
    rate_based_statement {
      limit                 = var.addon_wafx_rate_limit      # 최소 10
      aggregate_key_type    = "IP"
      evaluation_window_sec = var.addon_wafx_rate_window_sec # 60/120/300/600

      # 특정 경로만 셀 때. 전 경로면 이 블록을 지운다
      scope_down_statement {
        regex_match_statement {
          regex_string = var.addon_wafx_rate_path_regex
          field_to_match {
            uri_path {}
          }
          text_transformation {
            priority = 0
            type     = "NONE"
          }
        }
      }
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "rate-limit"
    sampled_requests_enabled   = true
  }
}
```

<details><summary><b>값 뽑기 — 세트별 (임계값이 채점 대상이다)</b></summary>

| 세트 | 기존 rate 룰 | 채점이 읽는 값 |
| --- | --- | --- |
| set-02 | 없음 | — |
| set-03 | `${var.name_prefix}-rate-limit`(3), **limit 200 / 60s** | mark 10-1: `RateBasedStatement.Limit <= 200` |
| set-07 | `unicorn-rate-limit`(3), **limit 50 / 60s** | 룰 이름·limit |

**기존 rate 룰이 이미 있으면 새로 추가하지 말고 `limit` 만 바꾼다.** 두 개가 되면 채점이 깨질 수 있다.

```powershell
$n = terraform output -raw waf_name; $i = terraform output -raw waf_id
aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name $n --id $i `
  --query "WebACL.Rules[?Statement.RateBasedStatement].[Name,Statement.RateBasedStatement.Limit,Statement.RateBasedStatement.EvaluationWindowSec]" --output table

# 임계 초과 유발 (반영까지 최대 수십 초)
$d = terraform output -raw cloudfront_domain
1..60 | ForEach-Object { curl.exe -s -o NUL -w "%{http_code} " "https://$d/v1/book" }
```

관리형 룰이 막을 때도 지정 본문이 나가야 하면 `rule_action_override` 의 `action_to_use { block { custom_response { ... } } }` 로 룰마다 건다 — **set-07 task-1 `waf.tf`** 가 그 패턴이다.
</details>

## 3. geo_match (국가 차단)

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# 기존 aws_wafv2_web_acl 리소스 블록 *안에*
rule {
  name     = "geo-block"
  priority = 50
  action {
    block {}
  }
  statement {
    geo_match_statement {
      country_codes = var.addon_wafx_geo_country_codes
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "geo-block"
    sampled_requests_enabled   = true
  }
}
```

허용 국가만 열려면 `not_statement { statement { geo_match_statement {...} } }` 로 감싼다.

<details><summary><b>값 뽑기 — 세트별 (CloudFront geo_restriction과 중복 주의)</b></summary>

**세 세트 모두 CloudFront에 `restrictions.geo_restriction` 블록이 이미 있다.** 어느 쪽을 채점하는지 과제지로 확인하고 **한 쪽만** 쓴다.

```powershell
# CloudFront 쪽
aws cloudfront get-distribution-config --id (terraform output -raw cloudfront_id) `
  --query "DistributionConfig.Restrictions.GeoRestriction"

# WAF 쪽
$n = terraform output -raw waf_name; $i = terraform output -raw waf_id
aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name $n --id $i `
  --query "WebACL.Rules[?Statement.GeoMatchStatement].[Name,Statement.GeoMatchStatement.CountryCodes]"
```

CloudFront 쪽이면 [cloudfront-hardening](../cloudfront-hardening/README.md) 2번이다.
</details>

## 4. byte_match — POST body 문자열

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# 기존 aws_wafv2_web_acl 리소스 블록 *안에*
rule {
  name     = "post-body-block"
  priority = 60
  action {
    block {}
  }
  statement {
    and_statement {
      statement {
        byte_match_statement {
          positional_constraint = "EXACTLY"
          search_string         = "POST"
          field_to_match {
            method {}
          }
          text_transformation {
            priority = 0
            type     = "NONE"
          }
        }
      }
      statement {
        byte_match_statement {
          positional_constraint = "CONTAINS"
          search_string         = "admin"
          field_to_match {
            body {}        # 기본 8KB 까지만 검사
          }
          text_transformation {
            priority = 0
            type     = "LOWERCASE"
          }
        }
      }
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "post-body-block"
    sampled_requests_enabled   = true
  }
}
```

문자열이 여럿이면 두 번째 statement를 `or_statement` 로 감싼다 (`rules.tf` 는 변수 목록으로 dynamic 처리).

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 이런 룰이 **없다** — 새로 넣는다. POST 경로는 세트마다 다르다:

| 세트 | POST 경로 |
| --- | --- |
| set-02 | ALB 리스너 규칙 `.book_post` |
| set-03 | Ingress → 앱 |
| set-07 | ALB 리스너 규칙 `.post` |

```powershell
$d = terraform output -raw cloudfront_domain
curl.exe -s -o NUL -w "%{http_code}`n" -X POST "https://$d/v1/book" -d "username=admin"   # 403

# 샘플 요청으로 어떤 룰이 잡았는지 확인
aws wafv2 get-sampled-requests --scope CLOUDFRONT --region us-east-1 `
  --web-acl-arn (terraform output -raw waf_arn) --rule-metric-name post-body-block `
  --time-window StartTime=$([DateTimeOffset]::UtcNow.AddMinutes(-10).ToUnixTimeSeconds()),EndTime=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) `
  --max-items 10 --query "SampledRequests[].[Action,Request.URI]"
```

`body {}` 는 기본 8KB(16KB)까지만 검사한다 — 초과분은 `oversize_handling` 으로 정한다(미지정 시 CONTINUE).
</details>

## 5. 헤더 값 불일치 차단

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# rule {} 의 statement 부분
not_statement {
  statement {
    byte_match_statement {
      positional_constraint = "EXACTLY"
      search_string         = var.addon_wafx_header_value
      field_to_match {
        single_header {
          name = var.addon_wafx_header_name   # 반드시 소문자
        }
      }
      text_transformation {
        priority = 0
        type     = "NONE"
      }
    }
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

CloudFront origin의 `custom_header` 값과 맞춰야 한다:

| 세트 | 기존 origin-verify 헤더 |
| --- | --- |
| set-02 | `custom_header` **있음** (ALB origin + S3 origin) — 값은 `cloudfront.tf` 참조 |
| set-03 | 없음 |
| set-07 | 없음 (VPC Origin이라 불필요) |

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
curl.exe -s -o NUL -w "%{http_code}`n" -H "x-api-key: $v" "https://$d/v1/book"   # 200
curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/v1/book"                       # 403
```
</details>

## 6. UA regex 차단 (인라인)

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# rule {} 의 statement 부분 — 패턴 하나면 regex set 없이 인라인
regex_match_statement {
  regex_string = "(?i)(sqlmap|nikto|nmap)"
  field_to_match {
    single_header { name = "user-agent" }
  }
  text_transformation {
    priority = 0
    type     = "NONE"
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 없다. 확인:

```powershell
$d = terraform output -raw cloudfront_domain
curl.exe -s -o NUL -w "%{http_code}`n" -A "sqlmap/1.0" "https://$d/"    # 403
curl.exe -s -o NUL -w "%{http_code}`n" -A "Mozilla/5.0" "https://$d/"   # 200
```
</details>

## 7. and_statement + 경로 regex set (task-3 scanner-ua 패턴)

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
resource "aws_wafv2_regex_pattern_set" "addon_api_paths" {
  provider = aws.use1                # CLOUDFRONT scope 면 필수 (set-03/set-07)
  name     = "${var.addon_wafx_name}-api-paths"
  scope    = var.addon_wafx_scope

  dynamic "regular_expression" {
    for_each = var.addon_wafx_api_path_regexes
    content {
      regex_string = regular_expression.value
    }
  }
}
```

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# 기존 aws_wafv2_web_acl 리소스 블록 *안에*
rule {
  name     = "scanner-ua"
  priority = 80
  action {
    block {}
  }
  statement {
    and_statement {
      statement {
        regex_pattern_set_reference_statement {
          arn = aws_wafv2_regex_pattern_set.addon_api_paths.arn
          field_to_match {
            uri_path {}
          }
          text_transformation {
            priority = 0
            type     = "URL_DECODE"
          }
          text_transformation {
            priority = 1
            type     = "NORMALIZE_PATH"
          }
        }
      }
      statement {
        regex_pattern_set_reference_statement {
          arn = aws_wafv2_regex_pattern_set.addon_scanner_uas.arn
          field_to_match {
            single_header { name = "user-agent" }
          }
          text_transformation {
            priority = 0
            type     = "COMPRESS_WHITE_SPACE"
          }
          text_transformation {
            priority = 1
            type     = "LOWERCASE"
          }
        }
      }
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "scanner-ua"
    sampled_requests_enabled   = true
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**regex pattern set은 Web ACL과 같은 scope·리전이어야 한다.** set-03/set-07은 CLOUDFRONT이므로 set에도 `provider = aws.use1` 를 붙인다.

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "waf_api_paths_set_arn" { value = aws_wafv2_regex_pattern_set.addon_api_paths.arn }
```

```powershell
terraform output -raw waf_api_paths_set_arn
aws wafv2 list-regex-pattern-sets --scope CLOUDFRONT --region us-east-1 `
  --query "RegexPatternSets[].[Name,Id]" --output table
```

세트 `regular_expression` 은 **최대 10개**, **빈 목록은 API가 거부한다** — 룰을 끌 땐 세트 내용이 아니라 룰을 지운다 (task-3은 `__disabled__` 자리표시자를 쓴다).

완성 원본은 **task-3 `terraform/waf.tf`** 다.
</details>

## 8. 로깅 (redacted_fields · logging_filter)

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
# 기존 aws_wafv2_web_acl_logging_configuration 리소스 블록 *안에*
redacted_fields {
  single_header { name = "authorization" }
}

logging_filter {
  default_behavior = "DROP"
  filter {
    behavior    = "KEEP"
    requirement = "MEETS_ANY"
    condition {
      action_condition { action = "BLOCK" }
    }
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 로깅 구성 |
| --- | --- |
| set-02 | 없음 (ACL 자체가 없음) |
| set-03 | **없음** — 로그 그룹·리소스 정책·logging_configuration을 [waf](../waf/README.md) 3번에서 통째로 가져온다 |
| set-07 | `aws_cloudwatch_log_group.waf`(`aws-waf-logs-unicorn`) + `aws_cloudwatch_log_resource_policy.waf` + `aws_wafv2_web_acl_logging_configuration.unicorn` **전부 있음** |

```hcl
# 파일: set-07/task-1/terraform/outputs.tf
output "waf_log_group" { value = aws_cloudwatch_log_group.waf.name }
```

```powershell
# CLOUDFRONT 로그 그룹은 us-east-1 에 있다
aws logs tail (terraform output -raw waf_log_group) --region us-east-1 --since 10m
aws wafv2 get-logging-configuration --resource-arn (terraform output -raw waf_arn) --region us-east-1 `
  --query "LoggingConfiguration.[RedactedFields,LoggingFilter.DefaultBehavior]"
```

로그 그룹 이름은 **`aws-waf-logs-` 접두 강제**. `log_destination_configs` 에 `:*` 붙은 ARN은 거부된다 (task-3은 `trimsuffix`).
</details>

## VERIFY

```powershell
$n = terraform output -raw waf_name; $i = terraform output -raw waf_id
aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name $n --id $i `
  --query "WebACL.Rules[].[Priority,Name]" --output table

$d = terraform output -raw cloudfront_domain
curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/v1/x?id=1' OR 1=1--"   # 403
curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/"                       # 200
```

## TROUBLESHOOT

- 룰 추가·수정은 **in-place**. `name`·`scope` 변경은 재생성이고 연결도 끊긴다.
- **regex pattern set은 Web ACL과 같은 scope·리전.** CLOUDFRONT면 `provider = aws.use1`. 최대 10개, 빈 목록은 거부.
- CLOUDFRONT scope 리소스(Web ACL·regex set·로그 그룹)는 전부 us-east-1. alias 누락 시 plan은 통과하고 apply에서 `WAFInvalidParameterException`.
- managed rule group은 `and_statement` 로 감쌀 수 없다 — 경로 한정은 `scope_down_statement` 만. `scope_down_statement` 의 text_transformation은 룰 그룹 안으로 상속되지 않는다 (base64 우회는 task-3 `base64-sqli` 참고).
- `sqli_match_statement` `sensitivity_level = "HIGH"` **금지** — task-3 실측에서 정상 트래픽 수만 건을 차단했다. 커스텀 SQLi는 LOW.
- `rate_based_statement`: `limit` 최소 10, 윈도는 60/120/300/600만. 반영까지 최대 수십 초.
- `custom_response_body` 는 ACL 최상위 블록이고 `key` 로 룰에서 참조한다.
- `single_header.name` 은 소문자.
- `geo_match_statement` 와 CloudFront `restrictions.geo_restriction` 을 **중복 적용하지 않는다.**
- 채점이 `get-web-acl` 로 룰 이름·priority·limit을 읽는 세트가 있다 — **룰 이름은 과제지 표기 그대로.**

## 실전 구현 (참고용)

- set-07 task-1 `terraform/waf.tf` — CLOUDFRONT, `custom_response_body` + `rule_action_override` 로 관리형 룰에도 지정 본문, 로깅 완성본
- set-03 task-1 `terraform/waf.tf` — 커스텀 sqli/xss match, rate limit 200
- task-3 `terraform/waf.tf` — regex pattern set + scope_down, base64-sqli, `waf/scanner-ua.json`(콘솔 부착용 JSON 룰)
- [waf](../waf/README.md) — Web ACL 본체 + 로깅 + 연결

---

## 막히면 여는 순서

인자 이름이나 조합에서 막히면 ① 위 **실전 구현**(이미 apply 가 통과한 코드) → ② 로컬 스키마 명령 → ③ 공식 문서 순으로 연다. 대회장 인터넷은 공식 문서까지 열려 있다. 그래도 ①②를 먼저 여는 건 브라우저보다 빠르고, 블로그에서 인자 이름을 베껴 프로바이더·차트 버전이 어긋나는 일이 없어서다.

```powershell
terraform providers schema -json | jq '.provider_schemas[].resource_schemas["<리소스타입>"].block.attributes | keys'
aws <서비스> <명령> help
kubectl explain <리소스>.spec --recursive
```

리소스별 공식 문서 주소·이 저장소의 구현 위치·흔히 막히는 인자는 [DOC-LINKS 4절 리소스별 색인](../../../DOC-LINKS.md#4-리소스별-색인)에 한 줄씩 있다. 리소스 타입(`aws_s3_bucket` 등)으로 Ctrl+F 한다.

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), 세트별 리소스 주소는 [대조표](../../../KIT-INDEX.md#세트별-리소스-주소-대조표-task-1)(표에 없는 세트는 [주소 찾는 명령](../../../KIT-INDEX.md#표에-없는-세트는-직접-찾는다)), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
