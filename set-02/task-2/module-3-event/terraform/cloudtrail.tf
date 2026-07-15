# ---------------------------------------------------------------------------
# CloudTrail (과제지 5. CloudTrail — Management Events Read/Write)
# - sg-change / role-change / ec2-type-change 룰의 "AWS API Call via CloudTrail"
#   이벤트는 리전에 활성 트레일이 있어야만 EventBridge 로 전달된다.
# - 로그 버킷은 Config 딜리버리 채널과 공용 (cloudtrail/ · config/ prefix 분리)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  bucket        = "${var.logs_bucket_prefix}-${var.player_number}"
  force_destroy = true
}

data "aws_iam_policy_document" "logs_bucket" {
  # CloudTrail 딜리버리
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.trail_name}"]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
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
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.trail_name}"]
    }
  }

  # Config 딜리버리 (config.tf 딜리버리 채널)
  statement {
    sid       = "ConfigBucketCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.logs.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/config/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
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
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json
}

resource "aws_cloudtrail" "event" {
  name                          = var.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  # 과제지: Management Events Read/Write
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.logs]
}
