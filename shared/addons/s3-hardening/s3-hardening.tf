# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# 기존 버킷(var.addon_s3h_bucket_name) 보강: 버전 관리 · 수명주기 · 서버 액세스 로그 · EventBridge 알림.
# 전부 별도 리소스라 기존 aws_s3_bucket 은 건드리지 않는다. 이미 있는 항목(set-05/07 의 versioning 등)은 블록을 지운다.
# 원본: set-07/set-05 task-1 s3.tf (versioning), set-02 m1 s3.tf (notification)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_s3h" {}

resource "aws_s3_bucket_versioning" "addon" {
  bucket = var.addon_s3h_bucket_name
  versioning_configuration {
    status = "Enabled"
  }
}

# noncurrent 규칙은 버전 관리가 켜진 뒤에 의미가 있어 순서를 강제한다.
resource "aws_s3_bucket_lifecycle_configuration" "addon" {
  bucket = var.addon_s3h_bucket_name

  dynamic "rule" {
    for_each = var.addon_s3h_lifecycle_rules
    content {
      id     = rule.key
      status = "Enabled"

      # prefix "" 이면 filter {} (전체 객체)
      filter {
        prefix = rule.value.prefix != "" ? rule.value.prefix : null
      }

      dynamic "transition" {
        for_each = rule.value.transition_days > 0 ? [1] : []
        content {
          days          = rule.value.transition_days
          storage_class = rule.value.transition_storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days > 0 ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_days > 0 ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_days
        }
      }

      abort_incomplete_multipart_upload {
        days_after_initiation = 7
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.addon]
}

# ----- 서버 액세스 로그 -----
resource "aws_s3_bucket" "addon_s3_logs" {
  bucket        = "${var.addon_s3h_log_bucket_prefix}-${data.aws_caller_identity.addon_s3h.account_id}"
  force_destroy = true

  tags = { Name = "${var.addon_s3h_log_bucket_prefix}-${data.aws_caller_identity.addon_s3h.account_id}" }
}

resource "aws_s3_bucket_public_access_block" "addon_s3_logs" {
  bucket                  = aws_s3_bucket.addon_s3_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# BucketOwnerEnforced(기본) 버킷은 ACL 대신 버킷 정책으로 logging.s3.amazonaws.com 에 PutObject 를 준다.
data "aws_iam_policy_document" "addon_s3_logs" {
  statement {
    sid       = "S3ServerAccessLogsPolicy"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.addon_s3_logs.arn}/${var.addon_s3h_log_prefix}*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3:::${var.addon_s3h_bucket_name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.addon_s3h.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "addon_s3_logs" {
  bucket = aws_s3_bucket.addon_s3_logs.id
  policy = data.aws_iam_policy_document.addon_s3_logs.json

  depends_on = [aws_s3_bucket_public_access_block.addon_s3_logs]
}

resource "aws_s3_bucket_logging" "addon" {
  bucket        = var.addon_s3h_bucket_name
  target_bucket = aws_s3_bucket.addon_s3_logs.id
  target_prefix = var.addon_s3h_log_prefix

  depends_on = [aws_s3_bucket_policy.addon_s3_logs]
}

# ----- EventBridge 알림 -----
# 버킷당 notification 리소스는 하나뿐 — 기존 aws_s3_bucket_notification 이 있으면 거기에 eventbridge = true 만 추가.
resource "aws_s3_bucket_notification" "addon" {
  bucket      = var.addon_s3h_bucket_name
  eventbridge = true
}
