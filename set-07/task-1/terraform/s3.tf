# ---------------------------------------------------------------------------
# S3 (요구사항 5)
# - unicorn-web-<ACCOUNT_ID> : 정적 Frontend 서빙
# - 모든 퍼블릭 액세스 차단, 버전 관리, Data CMK 암호화
# - CloudFront OAC(배포 ARN)로만 접근
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

resource "aws_s3_bucket_versioning" "web" {
  bucket = aws_s3_bucket.web.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

# 제공된 정적 파일(index.html, main.jpeg)을 버킷 루트에 업로드.
# 소스는 repo 공용 디렉토리(shared/provided/task-1). 같은 디렉토리의 book 바이너리는
# App 컨테이너용이므로 S3 업로드에서 제외한다.
resource "aws_s3_object" "static" {
  for_each = setsubtract(fileset(local.provided_dir, "**"), ["book"])

  bucket                 = aws_s3_bucket.web.id
  key                    = each.value
  source                 = "${local.provided_dir}/${each.value}"
  source_hash            = filemd5("${local.provided_dir}/${each.value}")
  content_type           = lookup(local.content_types, regex("[^.]+$", each.value), "application/octet-stream")
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.data.arn
}

locals {
  provided_dir = "${path.module}/../../../shared/provided/task-1"
  content_types = {
    html = "text/html"
    jpeg = "image/jpeg"
    jpg  = "image/jpeg"
    png  = "image/png"
    css  = "text/css"
    js   = "application/javascript"
  }
}

# CloudFront(OAC) 가 객체를 읽을 수 있도록 하는 버킷 정책 (배포 ARN 만 허용)
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
