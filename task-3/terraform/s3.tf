# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = {
    Name = var.bucket_name
  }
}

# 퍼블릭 버킷 없이 /images/*를 제공하기 위한 OAC 동작 조건이다(보안 강화가 아니다).
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

  # 없는 키의 응답을 403 AccessDenied 대신 404 NoSuchKey 로 바꾸려는 것이다. S3 는 요청 주체에
  # s3:ListBucket 이 없으면 키 존재 여부를 감추려고 403 을 낸다. 과제지 7절은 404 를 요구한다.
  # 버킷 루트 ListObjects 노출은 cloudfront.tf 의 strip_images Function 이 막는다.
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]

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
