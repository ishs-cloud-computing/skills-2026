# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# WAF 부착 스니펫 — REGIONAL (ALB/API Gateway 앞)
# waf-regional.tf 와 waf-cloudfront.tf 중 **하나만** 복사한다 (리소스 이름이 같다).
# 원본: set-07 task-1 waf.tf. 경로 화이트리스트(scope-down)·base64 우회 대응이
# 필요하면 task-3 waf.tf 참고.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "addon" {
  name  = var.addon_waf_name
  scope = "REGIONAL"

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

# REGIONAL 은 association 리소스로 연결한다 (CLOUDFRONT 는 배포 쪽 web_acl_id).
resource "aws_wafv2_web_acl_association" "addon" {
  resource_arn = var.addon_waf_target_arn
  web_acl_arn  = aws_wafv2_web_acl.addon.arn
}

# ----- 로깅 (과제지가 요구할 때만 유지) -----
# 로그 그룹 이름은 aws-waf-logs- 접두어 강제.
resource "aws_cloudwatch_log_group" "addon_waf" {
  name              = "aws-waf-logs-${var.addon_waf_name}"
  retention_in_days = 30
}

data "aws_caller_identity" "addon_waf" {}
data "aws_region" "addon_waf" {}

# vended delivery 가 로그 그룹에 쓰도록 리소스 정책 부여 — 없으면 로그가 조용히 안 쌓인다.
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
      values   = ["arn:aws:logs:${data.aws_region.addon_waf.region}:${data.aws_caller_identity.addon_waf.account_id}:*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "addon_waf" {
  policy_name     = "aws-waf-logs-${var.addon_waf_name}-delivery"
  policy_document = data.aws_iam_policy_document.addon_waf_log_delivery.json
}

resource "aws_wafv2_web_acl_logging_configuration" "addon" {
  resource_arn            = aws_wafv2_web_acl.addon.arn
  log_destination_configs = [aws_cloudwatch_log_group.addon_waf.arn]

  depends_on = [aws_cloudwatch_log_resource_policy.addon_waf]
}
