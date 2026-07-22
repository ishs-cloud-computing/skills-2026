# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# S3 (과제지 2. CDN Function - 1. CDN 구성, 채점 2-1)
# - skillsphone-landing-ab-<ACCOUNT_ID>: Public Access 전부 차단, OAC 로만 접근
# - 제공 index_a/index_b.html 을 version-a/, version-b/ 아래에 업로드 (수정 금지)
# - 버킷 정책은 단일 Statement (채점 2-1 이 Statement[0] 의
#   Principal.Service / AWS:SourceArn 조건을 검사한다)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "landing" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = { Name = local.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "landing" {
  bucket = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "version_a" {
  bucket       = aws_s3_bucket.landing.id
  key          = trimprefix(var.version_a_path, "/")
  source       = "${path.module}/../../provided/Module2-CDN-Function/index_a.html"
  etag         = filemd5("${path.module}/../../provided/Module2-CDN-Function/index_a.html")
  content_type = "text/html"
}

resource "aws_s3_object" "version_b" {
  bucket       = aws_s3_bucket.landing.id
  key          = trimprefix(var.version_b_path, "/")
  source       = "${path.module}/../../provided/Module2-CDN-Function/index_b.html"
  etag         = filemd5("${path.module}/../../provided/Module2-CDN-Function/index_b.html")
  content_type = "text/html"
}

# OAC 접근만 허용: CloudFront 서비스 주체 + 본 배포 ARN 조건 (최소 권한, 유의사항 11)
data "aws_iam_policy_document" "landing" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.landing.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "landing" {
  bucket = aws_s3_bucket.landing.id
  policy = data.aws_iam_policy_document.landing.json

  depends_on = [aws_s3_bucket_public_access_block.landing]
}
