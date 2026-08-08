# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = {
    Name = var.bucket_name
  }
}

# CloudFront(OAC)만 읽기 허용 — 퍼블릭 버킷 없이 /images/*를 제공하기 위한
# 기능 요구사항이다(보안 강화가 아니라 OAC 동작 조건).
data "aws_iam_policy_document" "cdn_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cdn_read" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.cdn_read.json
}
