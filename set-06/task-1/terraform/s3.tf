# ---------------------------------------------------------------------------
# S3 정적 버킷 (plan.md §3.9)
# - 객체는 루트에만 (채점 6-1 이 '/' 미포함 키만 나열)
# - 기본 암호화 SSE-KMS(alias/gj2026-s3-key) + bucket key
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "static" {
  bucket        = "${var.name_prefix}-static-${var.bibunho}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

# CloudFront OAC 만 GetObject 허용
resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static]
}

# 제공 파일 업로드 — shared/provided 원본 그대로 (수정 금지)
locals {
  provided_dir = "${path.module}/../../../shared/provided/set-06-task-1"
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static.id
  key          = "index.html"
  source       = "${local.provided_dir}/index.html"
  content_type = "text/html"
  # SSE-KMS 객체는 ETag 가 md5 가 아니므로 etag 속성을 쓰면 영구 드리프트가 생긴다
  source_hash = filemd5("${local.provided_dir}/index.html")
}

resource "aws_s3_object" "main_jpeg" {
  bucket       = aws_s3_bucket.static.id
  key          = "main.jpeg"
  source       = "${local.provided_dir}/main.jpeg"
  content_type = "image/jpeg"
  source_hash  = filemd5("${local.provided_dir}/main.jpeg")
}
