# 비정상 요청(SQLi 등 공격 페이로드) → 403 차단. WAF block 기본 응답코드가 403이라
# 과제의 "비정상 요청은 403" 요구와 그대로 맞는다.
#
# 차단/관찰 구분 기준: 정상 채점 트래픽 오차단(availability 점수 하락)이
# 403 처리율 손해보다 크므로, FP 위험이 낮은 룰만 처음부터 block 한다.
#   block: SQLiRuleSet, KnownBadInputsRuleSet
#   count: CommonRuleSet(NoUserAgent·SizeRestrictions 등 FP 위험) → 당일
#          sampled requests 확인 후 rule_action_override로 개별 block 전환
#   count→토글: requestid/uuid 쿼리스트링 누락 룰 (waf_v1_block_enabled)

resource "aws_wafv2_web_acl" "this" {
  provider = aws.use1
  name     = "skills-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "sqli"
    priority = 10

    override_action {
      none {} # 그룹 내 룰 액션(block) 그대로 사용
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "known-bad-inputs"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "common"
    priority = 30

    override_action {
      count {} # 관찰만. 유효 룰 확인 후 rule_action_override로 개별 block 전환
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }

  # /v1/* 인데 requestid= 또는 uuid= 쿼리스트링이 없는 요청.
  # POST는 값이 body에 있을 수 있어 기본 count — 실트래픽 확인 후 토글.
  rule {
    name     = "abnormal-v1-missing-token"
    priority = 40

    dynamic "action" {
      for_each = var.waf_v1_block_enabled ? [1] : []
      content {
        block {
          custom_response {
            response_code = 403
          }
        }
      }
    }

    dynamic "action" {
      for_each = var.waf_v1_block_enabled ? [] : [1]
      content {
        count {}
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "/v1/"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        statement {
          or_statement {
            statement {
              not_statement {
                statement {
                  byte_match_statement {
                    positional_constraint = "CONTAINS"
                    search_string         = "requestid="
                    field_to_match {
                      query_string {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
            statement {
              not_statement {
                statement {
                  byte_match_statement {
                    positional_constraint = "CONTAINS"
                    search_string         = "uuid="
                    field_to_match {
                      query_string {}
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
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "abnormal-v1-missing-token"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "skills-waf"
    sampled_requests_enabled   = true
  }
}
