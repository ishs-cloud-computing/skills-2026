# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

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
