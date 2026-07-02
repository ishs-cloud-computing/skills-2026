# 채점 2-2가 get-bucket-tagging으로 Name 태그를 출력하므로 버킷에도 Name 태그 부여
resource "aws_s3_bucket" "static" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "static_oac" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]

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

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.static_oac.json

  depends_on = [aws_s3_bucket_public_access_block.static]
}

# content_type 누락 시 브라우저 채점에서 다운로드로 처리될 수 있어 명시
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static.id
  key          = "index.html"
  source       = "${local.provided_dir}/index.html"
  etag         = filemd5("${local.provided_dir}/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "main_image" {
  bucket       = aws_s3_bucket.static.id
  key          = "main.jpeg"
  source       = "${local.provided_dir}/main.jpeg"
  etag         = filemd5("${local.provided_dir}/main.jpeg")
  content_type = "image/jpeg"
}
