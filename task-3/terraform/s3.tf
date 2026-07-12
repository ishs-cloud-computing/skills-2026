resource "aws_s3_bucket" "this" {
  bucket = "${var.player_number}-bucket"

  tags = {
    Name = "${var.player_number}-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront(OAC)만 읽기 허용
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

  depends_on = [aws_s3_bucket_public_access_block.this]
}
