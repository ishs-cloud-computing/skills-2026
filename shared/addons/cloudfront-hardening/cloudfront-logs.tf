# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudFront 표준 로그(legacy, S3) 대상 버킷.
# 표준 로그는 awslogsdelivery 계정에 버킷 ACL FULL_CONTROL 이 있어야 쓴다 — 기본
# BucketOwnerEnforced 면 배포 갱신이 "does not enable ACL access" 로 실패하므로
# ownership 을 BucketOwnerPreferred 로 내리고 ACL 로 grant 한다.
# 배포 쪽 연결은 README 의 logging_config 블록.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_cfh" {}
data "aws_canonical_user_id" "addon_cfh" {}

resource "aws_s3_bucket" "addon_cf_logs" {
  bucket        = "${var.addon_cfh_log_bucket_prefix}-${data.aws_caller_identity.addon_cfh.account_id}"
  force_destroy = true

  tags = { Name = "${var.addon_cfh_log_bucket_prefix}-${data.aws_caller_identity.addon_cfh.account_id}" }
}

resource "aws_s3_bucket_public_access_block" "addon_cf_logs" {
  bucket                  = aws_s3_bucket.addon_cf_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "addon_cf_logs" {
  bucket = aws_s3_bucket.addon_cf_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# c4c1ede6... = CloudFront awslogsdelivery 계정 canonical ID (AWS 문서 고정값)
resource "aws_s3_bucket_acl" "addon_cf_logs" {
  bucket = aws_s3_bucket.addon_cf_logs.id

  access_control_policy {
    grant {
      grantee {
        id   = data.aws_canonical_user_id.addon_cfh.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
    grant {
      grantee {
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
    owner {
      id = data.aws_canonical_user_id.addon_cfh.id
    }
  }

  depends_on = [aws_s3_bucket_ownership_controls.addon_cf_logs, aws_s3_bucket_public_access_block.addon_cf_logs]
}
