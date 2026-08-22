# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# WAF 부착 스니펫 — CLOUDFRONT scope
# waf-regional.tf 와 waf-cloudfront.tf 중 **하나만** 복사한다 (리소스 이름이 같다).
#
# 전제: versions.tf 에 us-east-1 provider alias 가 있어야 한다.
#   provider "aws" { alias = "use1"  region = "us-east-1" }
# (set-07·set-05 task-1 versions.tf 에 이미 있음. 없는 세트는 이 블록을 추가한다.)
#
# 연결은 association 리소스가 아니라 CloudFront 배포 쪽에서 한다:
#   aws_cloudfront_distribution 리소스 안에  web_acl_id = aws_wafv2_web_acl.addon.arn
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "addon" {
  provider = aws.use1
  name     = var.addon_waf_name
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
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
    name     = "${var.addon_waf_name}-rate-limit"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit                 = var.addon_waf_rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = var.addon_waf_rate_window_sec
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.addon_waf_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.addon_waf_name
    sampled_requests_enabled   = true
  }

  tags = { Name = var.addon_waf_name }
}

# ----- 로깅 (과제지가 요구할 때만 유지) -----
# CLOUDFRONT scope 의 로그 그룹은 us-east-1 이어야 하고 aws-waf-logs- 접두어 강제.
resource "aws_cloudwatch_log_group" "addon_waf" {
  provider          = aws.use1
  name              = "aws-waf-logs-${var.addon_waf_name}"
  retention_in_days = 30
}

data "aws_caller_identity" "addon_waf" {}

data "aws_iam_policy_document" "addon_waf_log_delivery" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.addon_waf.arn}:*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.addon_waf.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.addon_waf.account_id}:*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "addon_waf" {
  provider        = aws.use1
  policy_name     = "aws-waf-logs-${var.addon_waf_name}-delivery"
  policy_document = data.aws_iam_policy_document.addon_waf_log_delivery.json
}

resource "aws_wafv2_web_acl_logging_configuration" "addon" {
  provider                = aws.use1
  resource_arn            = aws_wafv2_web_acl.addon.arn
  log_destination_configs = [aws_cloudwatch_log_group.addon_waf.arn]

  depends_on = [aws_cloudwatch_log_resource_policy.addon_waf]
}
