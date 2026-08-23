# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudTrail 하드닝 부착 스니펫 — 로그 버킷+정책 · 파일 무결성 검증 · 멀티리전 · management
# 이벤트 선택 · (선택) CloudWatch Logs 연동 · (선택) CMK(SSE-KMS)
# 원본: set-02 task-2 module-3-event(RC 판에서 삭제 — git 이력) cloudtrail.tf, set-08 task-2 module-3-event-handling cloudtrail.tf
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_trail" {}
data "aws_region" "addon_trail" {}

locals {
  addon_trail_arn = "arn:aws:cloudtrail:${data.aws_region.addon_trail.region}:${data.aws_caller_identity.addon_trail.account_id}:trail/${var.addon_trail_name}"
}

# ----- 로그 버킷 -----
resource "aws_s3_bucket" "addon_trail" {
  bucket        = "${var.addon_trail_bucket_prefix}-${data.aws_caller_identity.addon_trail.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "addon_trail" {
  bucket                  = aws_s3_bucket.addon_trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "addon_trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.addon_trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.addon_trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.addon_trail.arn}/${var.addon_trail_s3_key_prefix != "" ? "${var.addon_trail_s3_key_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.addon_trail.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.addon_trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "addon_trail" {
  bucket = aws_s3_bucket.addon_trail.id
  policy = data.aws_iam_policy_document.addon_trail_bucket.json
}

# ----- CloudWatch Logs 연동 (addon_trail_cw_logs_enabled) -----
resource "aws_cloudwatch_log_group" "addon_trail" {
  count = var.addon_trail_cw_logs_enabled ? 1 : 0

  name              = var.addon_trail_log_group_name
  retention_in_days = var.addon_trail_log_retention_days
  kms_key_id        = var.addon_trail_kms_enabled ? aws_kms_key.addon_trail[0].arn : null
}

data "aws_iam_policy_document" "addon_trail_cw_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_trail_cw" {
  count = var.addon_trail_cw_logs_enabled ? 1 : 0

  name               = "${var.addon_trail_name}-cwlogs-role"
  assume_role_policy = data.aws_iam_policy_document.addon_trail_cw_assume.json
}

data "aws_iam_policy_document" "addon_trail_cw" {
  count = var.addon_trail_cw_logs_enabled ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.addon_trail[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "addon_trail_cw" {
  count = var.addon_trail_cw_logs_enabled ? 1 : 0

  name   = "${var.addon_trail_name}-cwlogs-policy"
  role   = aws_iam_role.addon_trail_cw[0].id
  policy = data.aws_iam_policy_document.addon_trail_cw[0].json
}

# ----- CMK (addon_trail_kms_enabled) — cloudtrail 서비스 문장이 없으면 apply 가 InsufficientEncryptionPolicyException -----
data "aws_iam_policy_document" "addon_trail_kms" {
  statement {
    sid       = "EnableRoot"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.addon_trail.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudTrailEncrypt"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.addon_trail.account_id}:trail/*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.addon_trail_arn]
    }
  }

  statement {
    sid       = "AllowCloudTrailDescribe"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  # CloudWatch Logs 연동 시 로그 그룹 암호화에도 같은 키를 쓴다
  statement {
    sid       = "AllowCloudWatchLogs"
    effect    = "Allow"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.addon_trail.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.addon_trail.region}:${data.aws_caller_identity.addon_trail.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "addon_trail" {
  count = var.addon_trail_kms_enabled ? 1 : 0

  description             = "CloudTrail log encryption (${var.addon_trail_name})"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.addon_trail_kms.json
}

resource "aws_kms_alias" "addon_trail" {
  count = var.addon_trail_kms_enabled ? 1 : 0

  name          = "alias/${var.addon_trail_kms_alias}"
  target_key_id = aws_kms_key.addon_trail[0].key_id
}

# ----- Trail -----
resource "aws_cloudtrail" "addon" {
  name                          = var.addon_trail_name
  s3_bucket_name                = aws_s3_bucket.addon_trail.id
  s3_key_prefix                 = var.addon_trail_s3_key_prefix != "" ? var.addon_trail_s3_key_prefix : null
  include_global_service_events = var.addon_trail_include_global_events
  is_multi_region_trail         = var.addon_trail_multi_region
  enable_log_file_validation    = true
  enable_logging                = true
  kms_key_id                    = var.addon_trail_kms_enabled ? aws_kms_key.addon_trail[0].arn : null

  cloud_watch_logs_group_arn = var.addon_trail_cw_logs_enabled ? "${aws_cloudwatch_log_group.addon_trail[0].arn}:*" : null
  cloud_watch_logs_role_arn  = var.addon_trail_cw_logs_enabled ? aws_iam_role.addon_trail_cw[0].arn : null

  # 데이터 이벤트(S3 객체·Lambda 호출)가 필요하면 README 의 advanced_event_selector 블록으로 교체
  event_selector {
    read_write_type           = var.addon_trail_read_write_type
    include_management_events = true
  }

  tags = { Name = var.addon_trail_name }

  depends_on = [aws_s3_bucket_policy.addon_trail, aws_iam_role_policy.addon_trail_cw]
}
