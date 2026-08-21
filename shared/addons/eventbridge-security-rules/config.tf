# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# AWS Config — recorder + delivery channel + managed rule + (선택) SSM 자동 복구
# 원본: set-02 task-2 module-3-event config.tf·cloudtrail.tf(버킷 정책 Config 문장)
# recorder 는 리전당 1개 — 이미 있으면 addon_evb_config_enabled = false 로 끄고 룰만 쓴다.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_evb" {}

# ----- 딜리버리 버킷 -----
resource "aws_s3_bucket" "addon_evb_config" {
  count = var.addon_evb_config_enabled ? 1 : 0

  bucket        = "${var.addon_evb_config_bucket_prefix}-${data.aws_caller_identity.addon_evb.account_id}"
  force_destroy = true
}

data "aws_iam_policy_document" "addon_evb_config_bucket" {
  count = var.addon_evb_config_enabled ? 1 : 0

  statement {
    sid       = "ConfigBucketCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.addon_evb_config[0].arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.addon_evb.account_id]
    }
  }

  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.addon_evb_config[0].arn}/AWSLogs/${data.aws_caller_identity.addon_evb.account_id}/Config/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.addon_evb.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "addon_evb_config" {
  count = var.addon_evb_config_enabled ? 1 : 0

  bucket = aws_s3_bucket.addon_evb_config[0].id
  policy = data.aws_iam_policy_document.addon_evb_config_bucket[0].json
}

# ----- recorder -----
data "aws_iam_policy_document" "addon_evb_config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_evb_config" {
  count = var.addon_evb_config_enabled ? 1 : 0

  name               = var.addon_evb_config_role_name
  assume_role_policy = data.aws_iam_policy_document.addon_evb_config_assume.json
}

resource "aws_iam_role_policy_attachment" "addon_evb_config" {
  count = var.addon_evb_config_enabled ? 1 : 0

  role       = aws_iam_role.addon_evb_config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# 스코프를 채점 대상 타입으로 좁힌다 — 넓히면 태그 없는 관리형 리소스가 NON_COMPLIANT 를 만든다
resource "aws_config_configuration_recorder" "addon_evb" {
  count = var.addon_evb_config_enabled ? 1 : 0

  name     = "default"
  role_arn = aws_iam_role.addon_evb_config[0].arn

  recording_group {
    all_supported  = length(var.addon_evb_config_resource_types) == 0
    resource_types = var.addon_evb_config_resource_types
  }
}

resource "aws_config_delivery_channel" "addon_evb" {
  count = var.addon_evb_config_enabled ? 1 : 0

  name           = "default"
  s3_bucket_name = aws_s3_bucket.addon_evb_config[0].id

  depends_on = [aws_config_configuration_recorder.addon_evb, aws_s3_bucket_policy.addon_evb_config]
}

resource "aws_config_configuration_recorder_status" "addon_evb" {
  count = var.addon_evb_config_enabled ? 1 : 0

  name       = aws_config_configuration_recorder.addon_evb[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.addon_evb]
}

# ----- managed rules -----
resource "aws_config_config_rule" "addon_evb" {
  for_each = var.addon_evb_config_rules

  name = each.value.name

  source {
    owner             = "AWS"
    source_identifier = each.value.source_identifier
  }

  input_parameters = length(each.value.input_parameters) > 0 ? jsonencode(each.value.input_parameters) : null

  dynamic "scope" {
    for_each = length(each.value.resource_types) > 0 ? [1] : []
    content {
      compliance_resource_types = each.value.resource_types
    }
  }

  depends_on = [aws_config_configuration_recorder_status.addon_evb]
}

# ----- 자동 복구 예시: INCOMING_SSH_DISABLED → SSM Automation 으로 0.0.0.0/0 인바운드 제거 -----
data "aws_iam_policy_document" "addon_evb_remediation_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_evb_remediation" {
  count = var.addon_evb_remediation_rule_key != "" ? 1 : 0

  name               = "${var.addon_evb_config_rules[var.addon_evb_remediation_rule_key].name}-remediation-role"
  assume_role_policy = data.aws_iam_policy_document.addon_evb_remediation_assume.json
}

data "aws_iam_policy_document" "addon_evb_remediation" {
  statement {
    sid       = "RevokeSg"
    effect    = "Allow"
    actions   = ["ec2:DescribeSecurityGroups", "ec2:RevokeSecurityGroupIngress"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "addon_evb_remediation" {
  count = var.addon_evb_remediation_rule_key != "" ? 1 : 0

  name   = "remediation"
  role   = aws_iam_role.addon_evb_remediation[0].id
  policy = data.aws_iam_policy_document.addon_evb_remediation.json
}

resource "aws_config_remediation_configuration" "addon_evb" {
  count = var.addon_evb_remediation_rule_key != "" ? 1 : 0

  config_rule_name = aws_config_config_rule.addon_evb[var.addon_evb_remediation_rule_key].name
  resource_type    = "AWS::EC2::SecurityGroup"
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisablePublicAccessForSecurityGroup"
  automatic        = true

  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60

  parameter {
    name           = "GroupId"
    resource_value = "RESOURCE_ID"
  }

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.addon_evb_remediation[0].arn
  }
}
