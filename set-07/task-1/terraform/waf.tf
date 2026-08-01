# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# WAF (요구사항 10-3)
# - unicorn-waf : scope=CLOUDFRONT (us-east-1), 기본 동작 Allow
# - AWSManagedRulesCommonRuleSet / KnownBadInputsRuleSet (override None)
# - unicorn-rate-limit : 60초 내 동일 IP 50건 초과 시 Block (403 + custom body)
# - 로그 -> aws-waf-logs-unicorn (us-east-1, Platform CMK 암호화)
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "unicorn" {
  provider = aws.use1
  name     = "unicorn-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 차단 응답 본문 (rate-limit 규칙에서 사용)
  custom_response_body {
    key          = "unicorn-blocked"
    content      = "Request blocked by Unicorn WAF"
    content_type = "TEXT_PLAIN"
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
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
    name     = "unicorn-rate-limit"
    priority = 3
    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "unicorn-blocked"
        }
      }
    }
    statement {
      rate_based_statement {
        limit                 = 50
        aggregate_key_type    = "IP"
        evaluation_window_sec = 60
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "unicorn-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "unicorn-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "unicorn-waf" }
}

# ----- WAF 로그 그룹 (us-east-1, Platform CMK) -----
resource "aws_cloudwatch_log_group" "waf" {
  provider          = aws.use1
  name              = "aws-waf-logs-unicorn"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.platform_primary.arn

  tags = { Name = "aws-waf-logs-unicorn" }
}

# WAF 로그(CloudWatch Logs vended delivery)가 로그 그룹에 기록할 수 있도록 리소스 정책 부여
data "aws_iam_policy_document" "waf_log_delivery" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.waf.arn}:*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-1:${local.account_id}:*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  provider        = aws.use1
  policy_name     = "aws-waf-logs-unicorn-delivery"
  policy_document = data.aws_iam_policy_document.waf_log_delivery.json
}

resource "aws_wafv2_web_acl_logging_configuration" "unicorn" {
  provider                = aws.use1
  resource_arn            = aws_wafv2_web_acl.unicorn.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}
