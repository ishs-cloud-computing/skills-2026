# waf-extra-rules 부착 스니펫

기존 Web ACL 에 **룰 블록**을 추가하는 템플릿 모음. Web ACL 자체를 새로 만드는 건 `shared/addons/waf/`.
1과제 WAF 옵션 확장(set-02/03/05/07/08/09 task-1), task-3 WAF 추가 룰, set-07 m2 CDN WAF 에 대응한다.

## 파일

- `rules.tf` — 예시 Web ACL 하나에 룰 8종을 담고 `locals.addon_wafx_enable` 토글로 켠다 + regex pattern set 2개(경로·스캐너 UA). 기존 ACL 에 붙일 땐 아래 블록만 복사하고 이 파일의 ACL 은 쓰지 않는다
- `variables.tf` — `addon_wafx_*` 변수. 임계값·국가·문자열·regex 는 전부 tfvars 로 주입

## 부착 절차

1. **기존 Web ACL 이 있으면** 아래 블록 중 필요한 `rule {}` 을 그 `aws_wafv2_web_acl` 리소스 안에 복사한다. regex pattern set 을 쓰는 룰이면 `rules.tf` 의 `aws_wafv2_regex_pattern_set` 과 `variables.tf` 의 해당 변수도 같이 복사한다.
   **Web ACL 이 없으면** `rules.tf`·`variables.tf` 를 통째로 `set-XX/task-Y/terraform/` 으로 복사하고 `locals.addon_wafx_enable` 에서 필요한 룰만 `true` 로 둔다. 연결은 `shared/addons/waf/README` 와 같다(REGIONAL 은 `aws_wafv2_web_acl_association`, CLOUDFRONT 는 배포의 `web_acl_id`).
2. `terraform.tfvars`:

   ```hcl
   addon_wafx_name               = "skills-waf"
   addon_wafx_scope              = "REGIONAL"          # CLOUDFRONT 면 rules.tf 리소스 전부에 provider = aws.use1 추가
   addon_wafx_block_body         = "Request blocked"   # 과제지 지정 문자열
   addon_wafx_api_path_regexes   = ["^/v1/.*$", "^/health$"]
   addon_wafx_rate_limit         = 100
   addon_wafx_rate_window_sec    = 60
   addon_wafx_rate_path_regex    = "^/v1/.*$"          # "" 이면 전 경로
   addon_wafx_common_count_rules = ["SizeRestrictions_BODY"]
   addon_wafx_geo_country_codes  = ["CN", "RU"]
   addon_wafx_post_body_strings  = ["admin", "sysop"]
   addon_wafx_header_name        = "x-origin-verify"
   addon_wafx_header_value       = "<헤더 값>"
   addon_wafx_ua_regexes         = ["sqlmap", "nikto"]
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음(Web ACL 은 in-place update) 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws wafv2 get-web-acl --scope REGIONAL --name skills-waf --id <ID> --query 'WebACL.Rules[].[Name,Priority]' --output table   # CLOUDFRONT 는 --region us-east-1
   curl.exe -s -o NUL -w "%{http_code}`n" "https://<도메인>/v1/x?id=1' OR 1=1--"   # 403
   ```

## 블록

전부 `aws_wafv2_web_acl` 리소스 안의 `rule {}` 이다. `priority` 는 ACL 안에서 유일해야 한다(기존 룰과 겹치면 바꾼다).
`visibility_config` 는 룰마다 필수.

### 관리형 룰 그룹 (SQLi / IP 평판 / Common + COUNT 강등)

```hcl
# aws_wafv2_web_acl 리소스 안에:
rule {
  name     = "sqli"
  priority = 10
  override_action {
    none {}
  }
  statement {
    managed_rule_group_statement {
      vendor_name = "AWS"
      name        = "AWSManagedRulesSQLiRuleSet"   # AWSManagedRulesAmazonIpReputationList / AWSManagedRulesCommonRuleSet / AWSManagedRulesKnownBadInputsRuleSet

      # 경로 한정이 필요할 때만 — managed rule group 은 and_statement 로 감쌀 수 없다.
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

      # 특정 하위 룰만 COUNT 로 강등(오탐 방지) — CommonRuleSet 에서 주로 SizeRestrictions_BODY, NoUserAgent_HEADER
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

### rate-based + 경로 scope-down + 403 custom body

```hcl
# aws_wafv2_web_acl 리소스 안에 (custom_response_body 는 rule 밖, ACL 최상위):
custom_response_body {
  key          = "addon-blocked"
  content      = var.addon_wafx_block_body
  content_type = "TEXT_PLAIN"
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
      limit                 = var.addon_wafx_rate_limit
      aggregate_key_type    = "IP"
      evaluation_window_sec = var.addon_wafx_rate_window_sec

      # 특정 경로만 셀 때. 전 경로면 블록 삭제.
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

관리형 룰이 막을 때도 지정 본문이 나가야 하면 `rule_action_override` 의 `action_to_use { block { custom_response { ... } } }` 로 룰마다 건다(set-07 task-1 `waf.tf` 의 `waf_xss_rules` 패턴).

### geo_match (국가 차단)

```hcl
# aws_wafv2_web_acl 리소스 안에:
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

### byte_match — POST body 문자열 / 헤더 / UA regex

```hcl
# aws_wafv2_web_acl 리소스 안에 — POST 이면서 body 에 문자열 포함 (set-05 task-1):
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
            body {}
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

문자열이 여럿이면 두 번째 statement 를 `or_statement { statement {...} statement {...} }` 로 감싼다(`rules.tf` 는 변수 목록으로 dynamic 처리).

```hcl
# 헤더 값 불일치(또는 없음) 차단 — statement 부분만:
not_statement {
  statement {
    byte_match_statement {
      positional_constraint = "EXACTLY"
      search_string         = var.addon_wafx_header_value
      field_to_match {
        single_header {
          name = var.addon_wafx_header_name   # 소문자
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

```hcl
# UA regex 차단 — statement 부분만 (인라인 regex, 패턴 하나):
regex_match_statement {
  regex_string = "(?i)(sqlmap|nikto|nmap)"
  field_to_match {
    single_header {
      name = "user-agent"
    }
  }
  text_transformation {
    priority = 0
    type     = "NONE"
  }
}
```

### and_statement + 경로 regex set (task-3 scanner-ua 패턴)

```hcl
# 새 리소스 (Web ACL 과 같은 scope·리전):
resource "aws_wafv2_regex_pattern_set" "addon_api_paths" {
  name  = "${var.addon_wafx_name}-api-paths"
  scope = var.addon_wafx_scope   # CLOUDFRONT 면 provider = aws.use1

  dynamic "regular_expression" {
    for_each = var.addon_wafx_api_path_regexes
    content {
      regex_string = regular_expression.value
    }
  }
}

# aws_wafv2_web_acl 리소스 안에:
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
            single_header {
              name = "user-agent"
            }
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

### 로깅 (redacted_fields · logging_filter 추가)

로그 그룹·리소스 정책·`aws_wafv2_web_acl_logging_configuration` 본체는 `shared/addons/waf/waf-*.tf` 의 "로깅" 절을 복사한다.
과제지가 "특정 헤더 마스킹" 이나 "차단 요청만 기록" 을 요구하면 그 리소스에 추가:

```hcl
# aws_wafv2_web_acl_logging_configuration 리소스 안에:
redacted_fields {
  single_header {
    name = "authorization"
  }
}

logging_filter {
  default_behavior = "DROP"
  filter {
    behavior    = "KEEP"
    requirement = "MEETS_ANY"
    condition {
      action_condition {
        action = "BLOCK"
      }
    }
  }
}
```

## 함정

- 룰 추가·수정은 Web ACL **in-place update**. 단 `name`·`scope` 변경은 ⚠ 재생성(연결도 끊긴다).
- **regex pattern set 은 Web ACL 과 같은 scope·리전**이어야 한다. CLOUDFRONT 면 set 도 `provider = aws.use1`. 세트 `regular_expression` 은 최대 10개. 빈 목록은 API 가 거부한다 — 룰을 끌 땐 세트 내용이 아니라 룰을 지운다(task-3 은 `__disabled__` 자리표시자 사용).
- CLOUDFRONT scope 리소스(Web ACL·regex set·로그 그룹)는 전부 us-east-1. provider alias `use1` 필요 — 없으면 `versions.tf` 에 추가(`shared/addons/waf/README` 블록). 누락 시 plan 은 통과하고 apply 에서 WAFInvalidParameterException.
- managed rule group 은 `and_statement` 로 감쌀 수 없다 — 경로 한정은 `scope_down_statement` 만. `scope_down_statement` 의 text_transformation 은 룰 그룹 안으로 상속되지 않는다(base64 우회는 task-3 `base64-sqli` 커스텀 룰 참고).
- 관리형 `AWSManagedRulesCommonRuleSet` 은 body 8KB 초과·UA 없음 등으로 정상 트래픽을 막는다. 채점 스크립트의 curl 이 UA 없이 오면 `NoUserAgent_HEADER` 를 COUNT 로 강등한다.
- `sqli_match_statement` `sensitivity_level = "HIGH"` 는 금지 — task-3 실측에서 정상 트래픽 수만 건을 차단했다. 커스텀 SQLi 는 LOW.
- `rate_based_statement`: `limit` 최소 10, `evaluation_window_sec` 는 60/120/300/600 만. 채점이 "N 회 초과 시 차단" 을 보면 `limit = N` (limit 자체가 임계, 초과 판정은 WAF 가 한다). 반영까지 최대 수십 초.
- `custom_response_body` 는 ACL 최상위 블록이고 `key` 로 룰에서 참조한다. `content_type` 은 TEXT_PLAIN/TEXT_HTML/APPLICATION_JSON.
- `single_header.name` 은 소문자. `body {}` 는 기본 8KB(16KB) 까지만 검사 — 초과분은 `oversize_handling` 으로 정한다(미지정 시 CONTINUE).
- `geo_match_statement` 는 국가 코드만. CloudFront 의 `restrictions.geo_restriction` 과 중복 적용하지 않는다(어느 쪽을 채점하는지 과제지 확인).
- WAF 로그 그룹 이름은 `aws-waf-logs-` 접두 강제. `log_destination_configs` 에 `:*` 붙은 ARN 은 거부된다(task-3 은 `trimsuffix`).
- 채점이 `get-web-acl` 로 룰 이름·priority·limit 값을 읽는 세트(set-03 mark 10-1: `RateBasedStatement.Limit <= 200`)가 있다 — 룰 이름은 과제지 표기 그대로.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/waf.tf` — CLOUDFRONT, custom_response_body + rule_action_override 로 관리형 룰에도 지정 본문, 로깅
- set-05 task-1 `terraform/waf.tf` — POST body 문자열 and/or byte_match
- set-03 task-1 `terraform/waf.tf` — 커스텀 sqli/xss match, rate limit 200
- task-3 `terraform/waf.tf` — regex pattern set + scope_down, base64-sqli, `waf/scanner-ua.json`(콘솔 부착용 JSON 룰)
- shared/addons/waf/ — Web ACL 본체 + 로깅 + 연결
