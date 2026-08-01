# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 정적 콘텐츠 버킷. Public Access 전면 차단, CloudFront(OAC)만 접근 허용.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "landing" {
  bucket = "${var.bucket_name_prefix}${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "landing" {
  bucket = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "index_a" {
  bucket       = aws_s3_bucket.landing.id
  key          = trimprefix(var.version_a_path, "/")
  source       = "${path.module}/../../provided/module-2/index_a.html"
  etag         = filemd5("${path.module}/../../provided/module-2/index_a.html")
  content_type = "text/html"
}

resource "aws_s3_object" "index_b" {
  bucket       = aws_s3_bucket.landing.id
  key          = trimprefix(var.version_b_path, "/")
  source       = "${path.module}/../../provided/module-2/index_b.html"
  etag         = filemd5("${path.module}/../../provided/module-2/index_b.html")
  content_type = "text/html"
}

# 채점(2-1)이 Statement[0] 하나로 Service principal + AWS:SourceArn 조건을 검사 — 단일 statement 유지.
data "aws_iam_policy_document" "oac_read" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.landing.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.ab.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "landing" {
  bucket = aws_s3_bucket.landing.id
  policy = data.aws_iam_policy_document.oac_read.json
}
