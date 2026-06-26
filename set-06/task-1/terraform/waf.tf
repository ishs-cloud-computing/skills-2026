# ---------------------------------------------------------------------------
# WAF (요구사항 13)
# - gj2026-waf-acl : CloudFront 연결 (scope=CLOUDFRONT → us-east-1 provider)
# - Rule1: ALB(book) 경로(/v1/book)에서 POST 외 메서드 → 405 "Method Not Allowed"
# - Rule2: Lambda 경로(/reservation)에서 client_id 가 "영문자로 시작 + 숫자 포함 +
#          영숫자만" 형식이 아니면 → 403 "Access Denied"
#          RE2 는 lookahead 미지원이므로 "영문자 시작·영숫자"(^[A-Za-z][A-Za-z0-9]*$)
#          와 "숫자 포함"([0-9]) 두 정규식의 AND 로 유효성을 표현한다.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "cdn" {
  provider = aws.use1
  name     = "gj2026-waf-acl"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  custom_response_body {
    key          = "method_not_allowed"
    content      = "Method Not Allowed"
    content_type = "TEXT_PLAIN"
  }
  custom_response_body {
    key          = "access_denied"
    content      = "Access Denied"
    content_type = "TEXT_PLAIN"
  }

  # Rule1: /v1/book 에 POST 가 아닌 메서드 → 405
  rule {
    name     = "block-non-post-book"
    priority = 1

    action {
      block {
        custom_response {
          response_code            = 405
          custom_response_body_key = "method_not_allowed"
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "/v1/book"
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
          not_statement {
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
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-non-post-book"
      sampled_requests_enabled   = true
    }
  }

  # Rule2: /reservation 의 client_id 형식 위반 → 403
  rule {
    name     = "block-bad-client-id"
    priority = 2

    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "access_denied"
        }
      }
    }

    statement {
      and_statement {
        # /reservation 경로
        statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "/reservation"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        # client_id 쿼리 파라미터 존재
        statement {
          byte_match_statement {
            positional_constraint = "CONTAINS"
            search_string         = "client_id="
            field_to_match {
              query_string {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        # 유효 형식이 아니면(= NOT(영문자시작·영숫자 AND 숫자포함)) 차단
        statement {
          not_statement {
            statement {
              and_statement {
                statement {
                  regex_match_statement {
                    regex_string = "^[A-Za-z][A-Za-z0-9]*$"
                    field_to_match {
                      single_query_argument {
                        name = "client_id"
                      }
                    }
                    text_transformation {
                      priority = 0
                      type     = "URL_DECODE"
                    }
                  }
                }
                statement {
                  regex_match_statement {
                    regex_string = "[0-9]"
                    field_to_match {
                      single_query_argument {
                        name = "client_id"
                      }
                    }
                    text_transformation {
                      priority = 0
                      type     = "URL_DECODE"
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
      metric_name                = "block-bad-client-id"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "gj2026-waf-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "gj2026-waf-acl" }
}
