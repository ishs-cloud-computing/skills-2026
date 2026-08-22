# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# WAF 추가 룰 템플릿. 예시 Web ACL 하나에 룰을 전부 담고 locals 토글로 켠다.
# 기존 Web ACL 에 붙일 때는 README 의 블록을 그 리소스 안으로 복사하고 이 ACL 은 쓰지 않는다.
# 원본: set-07/set-05/set-03 task-1 waf.tf, task-3 waf.tf + waf/scanner-ua.json
# CLOUDFRONT scope 면 아래 리소스 전부에 provider = aws.use1 추가 (regex set 도 같은 리전·scope 필수).
# ---------------------------------------------------------------------------

locals {
  addon_wafx_enable = {
    sqli          = true  # AWSManagedRulesSQLiRuleSet (경로 scope-down)
    ip_reputation = true  # AWSManagedRulesAmazonIpReputationList
    common        = true  # AWSManagedRulesCommonRuleSet + 일부 COUNT 강등
    rate_limit    = true  # rate_based + 경로 scope-down + 403 custom body
    geo           = false # 국가 차단
    post_body     = false # POST body 문자열 차단 (set-05)
    header        = false # 헤더 값 불일치 차단
    scanner_ua    = false # 경로 set AND UA regex set (task-3 scanner-ua)
  }
}

# 검사 대상 경로. scope-down/and 조건이 이 세트를 참조한다 — 여기 없는 경로는 통과(ALB 404 유지).
resource "aws_wafv2_regex_pattern_set" "addon_api_paths" {
  name  = "${var.addon_wafx_name}-api-paths"
  scope = var.addon_wafx_scope

  dynamic "regular_expression" {
    for_each = var.addon_wafx_api_path_regexes
    content {
      regex_string = regular_expression.value
    }
  }
}

resource "aws_wafv2_regex_pattern_set" "addon_scanner_uas" {
  name  = "${var.addon_wafx_name}-scanner-uas"
  scope = var.addon_wafx_scope

  dynamic "regular_expression" {
    for_each = var.addon_wafx_ua_regexes
    content {
      regex_string = regular_expression.value
    }
  }
}

resource "aws_wafv2_web_acl" "addon_rules" {
  name  = var.addon_wafx_name
  scope = var.addon_wafx_scope

  default_action {
    allow {}
  }

  # 차단 응답 본문. block { custom_response { custom_response_body_key } } 가 참조한다.
  custom_response_body {
    key          = "addon-blocked"
    content      = var.addon_wafx_block_body
    content_type = "TEXT_PLAIN"
  }

  # ----- 1. 관리형 SQLi (경로 scope-down) -----
  # managed rule group 은 and_statement 로 감쌀 수 없다 — 경로 한정은 scope_down_statement 만 가능.
  dynamic "rule" {
    for_each = local.addon_wafx_enable.sqli ? [1] : []
    content {
      name     = "sqli"
      priority = 10
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesSQLiRuleSet"

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
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "sqli"
        sampled_requests_enabled   = true
      }
    }
  }

  # ----- 2. IP 평판 목록 -----
  dynamic "rule" {
    for_each = local.addon_wafx_enable.ip_reputation ? [1] : []
    content {
      name     = "ip-reputation"
      priority = 20
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesAmazonIpReputationList"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "ip-reputation"
        sampled_requests_enabled   = true
      }
    }
  }

  # ----- 3. CommonRuleSet + 일부 룰 COUNT 강등 -----
  dynamic "rule" {
    for_each = local.addon_wafx_enable.common ? [1] : []
    content {
      name     = "common"
      priority = 30
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesCommonRuleSet"

          dynamic "rule_action_override" {
            for_each = var.addon_wafx_common_count_rules
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "common"
        sampled_requests_enabled   = true
      }
    }
  }

  # ----- 4. rate limit (경로 scope-down, 403 + custom body) -----
  dynamic "rule" {
    for_each = local.addon_wafx_enable.rate_limit ? [1] : []
    content {
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

          dynamic "scope_down_statement" {
            for_each = var.addon_wafx_rate_path_regex != "" ? [1] : []
            content {
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
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  # ----- 5. 국가 차단 -----
  dynamic "rule" {
    for_each = local.addon_wafx_enable.geo ? [1] : []
    content {
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
  }

  # ----- 6. POST body 문자열 차단 (set-05) -----
  dynamic "rule" {
    for_each = local.addon_wafx_enable.post_body ? [1] : []
    content {
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
            or_statement {
              dynamic "statement" {
                for_each = var.addon_wafx_post_body_strings
                content {
                  byte_match_statement {
                    positional_constraint = "CONTAINS"
                    search_string         = statement.value
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
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "post-body-block"
        sampled_requests_enabled   = true
      }
    }
  }

  # ----- 7. 헤더 값 불일치 차단 (헤더 없음 포함) -----
  dynamic "rule" {
    for_each = local.addon_wafx_enable.header ? [1] : []
    content {
      name     = "header-check"
      priority = 70
      action {
        block {}
      }
      statement {
        not_statement {
          statement {
            byte_match_statement {
              positional_constraint = "EXACTLY"
              search_string         = var.addon_wafx_header_value
              field_to_match {
                single_header {
                  name = var.addon_wafx_header_name
                }
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
        metric_name                = "header-check"
        sampled_requests_enabled   = true
      }
    }
  }

  # ----- 8. 경로 set AND 스캐너 UA set (task-3 scanner-ua.json) -----
  dynamic "rule" {
    for_each = local.addon_wafx_enable.scanner_ua ? [1] : []
    content {
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
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.addon_wafx_name
    sampled_requests_enabled   = true
  }

  tags = { Name = var.addon_wafx_name }
}
