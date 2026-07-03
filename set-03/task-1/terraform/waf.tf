# ---------------------------------------------------------------------------
# WAF (요구사항 13)
# - wsc2026-waf : scope=CLOUDFRONT (us-east-1), 기본 동작 Allow
# - SQLi / XSS : 쿼리스트링 대상 커스텀 매치 룰로 결정적 403
#   (mark 10-1 이 booking_id 쿼리스트링에 SQLi/XSS 페이로드를 넣어 403 확인)
# - wsc2026-rate-limit : 60초 내 동일 IP 200건 이상 요청 차단
#   (mark 10-1 은 RateBasedStatement.Limit <= 200 설정값을 확인)
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "wsc2026" {
  provider = aws.use1
  name     = "wsc2026-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "wsc2026-sqli"
    priority = 1
    action {
      block {}
    }
    statement {
      sqli_match_statement {
        field_to_match {
          query_string {}
        }
        sensitivity_level = "HIGH"
        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "wsc2026-sqli"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "wsc2026-xss"
    priority = 2
    action {
      block {}
    }
    statement {
      xss_match_statement {
        field_to_match {
          query_string {}
        }
        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }
        text_transformation {
          priority = 1
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "wsc2026-xss"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "wsc2026-rate-limit"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit                 = 200
        aggregate_key_type    = "IP"
        evaluation_window_sec = 60
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "wsc2026-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "wsc2026-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "wsc2026-waf" }
}
