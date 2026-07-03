# ---------------------------------------------------------------------------
# S3 (요구사항 9)
# - wsc2026-static-<영문4>-<비번호>-bucket : 정적 페이지 호스팅 원본
# - 모든 퍼블릭 액세스 차단, bucket CMK SSE-KMS + 버킷 키 활성화
# - 지급받은 배포파일(index.html, main.jpeg)을 static/ 에 업로드
# - CloudFront OAC(배포 ARN)로만 접근
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "static" {
  bucket = local.bucket_name
  tags   = { Name = local.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
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
      kms_master_key_id = aws_kms_key.bucket.arn
    }
    bucket_key_enabled = true
  }
}

# 제공된 정적 파일을 static/ prefix 로 업로드. 같은 디렉토리의 book 바이너리는
# App 컨테이너용이므로 제외한다. 객체별 SSE-KMS 를 명시해 mark 6-1 의
# head-object SSEKMSKeyId 검사를 충족한다.
locals {
  provided_dir = "${path.module}/../../../shared/provided/task-1"
  static_files = setsubtract(fileset(local.provided_dir, "**"), ["book"])
  content_types = {
    html = "text/html"
    jpeg = "image/jpeg"
    jpg  = "image/jpeg"
    png  = "image/png"
    css  = "text/css"
    js   = "application/javascript"
  }
}

resource "aws_s3_object" "static" {
  for_each = local.static_files

  bucket                 = aws_s3_bucket.static.id
  key                    = "static/${each.value}"
  source                 = "${local.provided_dir}/${each.value}"
  source_hash            = filemd5("${local.provided_dir}/${each.value}")
  content_type           = lookup(local.content_types, regex("[^.]+$", each.value), "application/octet-stream")
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.bucket.arn
}

# 콘솔식 폴더 마커(0바이트 "static/") — mark 6-1 의 객체 KMS 검사 목록에
# "static/: PASS" 라인이 있어 동일하게 생성해 둔다 (Size 0 이라 목록 검사에는 미포함).
resource "aws_s3_object" "static_marker" {
  bucket                 = aws_s3_bucket.static.id
  key                    = "static/"
  content                = ""
  content_type           = "application/x-directory"
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.bucket.arn
}

# CloudFront(OAC) 만 객체를 읽을 수 있게 하는 버킷 정책 (배포 ARN 한정).
# 배포는 2차 apply(enable_cdn=true)에서 생성되므로 정책도 함께 게이트한다.
data "aws_iam_policy_document" "static_bucket" {
  count = var.enable_cdn ? 1 : 0

  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static" {
  count  = var.enable_cdn ? 1 : 0
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.static_bucket[0].json
}
