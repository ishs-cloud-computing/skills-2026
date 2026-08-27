# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# S3 (요구사항 4)
# - wskorea26-concert-bucket-<비번호> : 정적 웹(index.html, main.jpeg) 서빙
# - 모든 퍼블릭 액세스 차단(mark 2-2), 객체는 wskorea26-s3-key 로 SSE-KMS 암호화
# - 객체 경로 web/main/ (mark 2-1), CloudFront OAC(배포 ARN)로만 접근
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "web" {
  bucket = local.bucket_name
  tags   = { Name = local.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

# 제공된 정적 파일을 web/main/ 에 업로드 (mark 2-1 이 두 키를 정확히 검사).
# 같은 디렉토리의 book 바이너리는 컨테이너용이므로 제외한다.
resource "aws_s3_object" "static" {
  for_each = toset(["index.html", "main.jpeg"])

  bucket                 = aws_s3_bucket.web.id
  key                    = "${var.object_prefix}/${each.value}"
  source                 = "${local.provided_dir}/${each.value}"
  source_hash            = filemd5("${local.provided_dir}/${each.value}")
  content_type           = lookup(local.content_types, regex("[^.]+$", each.value), "application/octet-stream")
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.s3.arn
}

locals {
  content_types = {
    html = "text/html"
    jpeg = "image/jpeg"
    jpg  = "image/jpeg"
  }
}

# CloudFront(OAC)가 객체를 읽을 수 있도록 하는 버킷 정책 (배포 ARN 만 허용).
# 정책이 있어야 mark 2-2 의 get-bucket-policy-status 가 False 를 반환한다.
data "aws_iam_policy_document" "web_bucket" {
  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket.json
}
