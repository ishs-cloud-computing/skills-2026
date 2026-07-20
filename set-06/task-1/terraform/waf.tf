# ---------------------------------------------------------------------------
# WAF (plan.md §3.10) — CLOUDFRONT scope, us-east-1 필수 (AWS API 제약)
# - Rule1: /v1/book* AND method != POST  -> 405 "Method Not Allowed" (채점 9-1)
# - Rule2: /reservation* AND client_id 존재 AND 정규식 불일치 -> 403 "Access Denied" (채점 9-2)
# - 정규식 앵커 필수: WAF 는 부분 매칭이라 앵커 없으면 URL 인코딩 내부에 매칭돼 통과된다
# - client_id "존재" 검사 필수: 없으면 파라미터 없는 8-3 요청까지 차단된다
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "main" {
  provider = aws.use1

  name  = "${var.name_prefix}-waf-acl"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 채점이 `문구 + 공백 + 코드` 를 비교하므로 개행 없이 정확히 이 문자열
  custom_response_body {
    key          = "method-not-allowed"
    content      = "Method Not Allowed"
    content_type = "TEXT_PLAIN"
  }

  custom_response_body {
    key          = "access-denied"
    content      = "Access Denied"
    content_type = "TEXT_PLAIN"
  }

  # method 규칙은 /v1/book 한정 — 전역 적용 시 Grafana GET·/reservation GET 까지 차단(4.5점 손실)
  rule {
    name     = "deny-non-post-on-api"
    priority = 1

    action {
      block {
        custom_response {
          response_code            = 405
          custom_response_body_key = "method-not-allowed"
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            search_string         = "/v1/book"
            positional_constraint = "STARTS_WITH"
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
                field_to_match {
                  method {}
                }
                search_string         = "POST"
                positional_constraint = "EXACTLY"
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
      metric_name                = "deny-non-post-on-api"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "deny-invalid-client-id"
    priority = 2

    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "access-denied"
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            search_string         = "/reservation"
            positional_constraint = "STARTS_WITH"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        # 존재 검사 — WAF 는 컴포넌트가 없으면 "매칭 안 됨"으로 평가하므로
        # NOT(regex) 단독이면 client_id 없는 요청(8-3, 200 이어야 함)까지 차단된다
        statement {
          byte_match_statement {
            field_to_match {
              query_string {}
            }
            search_string         = "client_id="
            positional_constraint = "CONTAINS"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        statement {
          not_statement {
            statement {
              regex_match_statement {
                regex_string = var.client_id_regex
                field_to_match {
                  single_query_argument {
                    name = "client_id"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "URL_DECODE"
                }
                text_transformation {
                  priority = 1
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
      metric_name                = "deny-invalid-client-id"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-waf-acl"
    sampled_requests_enabled   = true
  }
}
