# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 존재하는 엔드포인트 목록. 모든 룰의 scope-down 조건이라 여기 없는 경로는 WAF가 판정하지 않고
# 그대로 통과 → ALB 기본액션 404. 과제지 7절 "제공하는 API 외의 요청은 404"가 여기서 성립한다.
# WAF는 CloudFront에 붙어 ALB보다 앞이므로, scope-down 없이는 없는 경로의 비정상 요청도 403이 된다.
resource "aws_wafv2_regex_pattern_set" "api_paths" {
  provider = aws.use1
  name     = local.waf_api_paths_name
  scope    = "CLOUDFRONT"

  dynamic "regular_expression" {
    for_each = var.waf_api_path_regexes

    content {
      regex_string = regular_expression.value
    }
  }
}

# 스캐너 UA 목록. 경로·페이로드와 달리 부하 생성기(브라우저형 UA)와 교집합이 없어 판별력이 높다.
#
# 내용은 terraform이 관리하지 않는다. 당일 로그를 보고 실시간으로 채우는 값인데 apply는 본 PC
# 전용이라, 로그 분석 → tfvars → apply 왕복이 병목이 된다. 룰과 세트를 분리해 둔 이유가 이거다 —
# WAF 콘솔에서 세트 내용만 갈아끼우면 룰은 ARN 참조라 저장 즉시 새 패턴을 쓴다(README STEP 12).
# ignore_changes가 없으면 다음 apply가 콘솔 변경을 되돌린다.
resource "aws_wafv2_regex_pattern_set" "scanner_uas" {
  provider = aws.use1
  name     = local.waf_scanner_uas_name
  scope    = "CLOUDFRONT"

  # 어떤 User-Agent와도 일치하지 않는 자리표시자 = 룰이 사실상 꺼진 상태.
  # 빈 목록을 API가 받는지 문서에 없어 하나를 남긴다.
  regular_expression {
    regex_string = "__disabled__scanner__ua__"
  }

  lifecycle {
    ignore_changes = [regular_expression]
  }
}

resource "aws_wafv2_web_acl" "this" {
  provider = aws.use1
  name     = local.waf_name
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "sqli"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"

        # managed rule group은 and_statement로 감쌀 수 없다. scope_down_statement가 유일한 경로 한정 수단.
        scope_down_statement {
          regex_pattern_set_reference_statement {
            arn = aws_wafv2_regex_pattern_set.api_paths.arn

            field_to_match {
              uri_path {}
            }

            # 인코딩·상대경로로 화이트리스트를 우회하지 못하게 한다.
            # LOWERCASE는 넣지 않는다 — /V1/USER는 ALB에서도 404라 404가 맞는 응답이다.
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

        scope_down_statement {
          regex_pattern_set_reference_statement {
            arn = aws_wafv2_regex_pattern_set.api_paths.arn

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
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # 관리형 SQLiRuleSet 은 base64 로 감싼 페이로드를 못 잡는다. 관리형 룰그룹의 text transformation 은
  # 고정이고 BASE64_DECODE 가 없으며, 밖에서 주입할 수도 없다 — scope_down_statement 의 변환도
  # 룰그룹으로 상속되지 않는다. 실측: 평문 SQLi 는 403, 같은 페이로드의 base64 는 GET 404 · POST 201.
  # POST 는 차단은커녕 DB 에 행이 들어갔다.
  #
  # UA 축(scanner-ua)과 달리 이 룰은 당일 로그를 봐야 정해지는 값이 아니라 고정 룰이라 terraform 에 둔다.
  # priority 30 은 당일 콘솔에서 붙일 scanner-ua 자리로 비워둔다.
  rule {
    name     = "base64-sqli"
    priority = 40

    action {
      block {}
    }

    statement {
      and_statement {
        # 관리형 룰의 scope_down_statement 와 동등한 경로 조건. 이게 빠지면 미제공 경로가
        # 404 대신 403 으로 나가 과제지 7절과 어긋난다.
        statement {
          regex_pattern_set_reference_statement {
            arn = aws_wafv2_regex_pattern_set.api_paths.arn

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
          or_statement {
            # 파라미터 단위로 본다. QUERY_STRING 전체는 &·= 때문에 유효한 base64 가 아니라
            # strict BASE64_DECODE 가 실패한다.
            statement {
              sqli_match_statement {
                # HIGH 는 금지 — 연습 세션에서 정상 트래픽 24,220건을 차단한 설정이다.
                sensitivity_level = "LOW"

                field_to_match {
                  all_query_arguments {}
                }

                text_transformation {
                  priority = 0
                  type     = "URL_DECODE"
                }

                text_transformation {
                  priority = 1
                  type     = "BASE64_DECODE"
                }

                # base64 를 푼 결과가 또 URL 인코딩인 경우(`%27%20OR%201=1--`)를 위해 한 번 더 푼다.
                # 이게 없으면 이중 인코딩 계열이 통째로 샌다 — 실측에서 이 페이로드만 200 이었다.
                text_transformation {
                  priority = 2
                  type     = "URL_DECODE"
                }
              }
            }

            # WAF 는 JSON 을 파싱해 값을 추출한 뒤에 text transformation 을 적용한다.
            statement {
              sqli_match_statement {
                sensitivity_level = "LOW"

                field_to_match {
                  json_body {
                    match_scope       = "VALUE"
                    oversize_handling = "CONTINUE"

                    match_pattern {
                      all {}
                    }
                  }
                }

                text_transformation {
                  priority = 0
                  type     = "BASE64_DECODE"
                }

                # 쿼리 쪽과 같은 이유 — 디코드 결과가 또 URL 인코딩일 수 있다.
                text_transformation {
                  priority = 1
                  type     = "URL_DECODE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "base64-sqli"
      sampled_requests_enabled   = true
    }
  }

  # scanner-ua 룰은 여기 없다. 당일 필요할 때 콘솔에서 waf/scanner-ua.json 을 붙여넣는다
  # (README STEP 12). 위 두 세트의 ARN 을 output 으로 뽑아 그 JSON 에 채운다.

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.waf_name
    sampled_requests_enabled   = true
  }
}

# CLOUDFRONT scope Web ACL의 로그 그룹은 같은 리전(us-east-1)이어야 하고 이름이 aws-waf-logs- 로 시작해야 한다.
resource "aws_cloudwatch_log_group" "waf" {
  provider          = aws.use1
  name              = local.waf_log_group
  retention_in_days = 1
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  provider     = aws.use1
  resource_arn = aws_wafv2_web_acl.this.arn
  # PutLoggingConfiguration은 ":*" 없는 로그 그룹 ARN만 받는다.
  log_destination_configs = [trimsuffix(aws_cloudwatch_log_group.waf.arn, ":*")]
}
