# S3 (과제지 7. S3 — mark 4-1 head-bucket)
# alert JSON 저장 + provided Go 바이너리 스테이징(bin/app — producer EC2 가 다운로드)
resource "aws_s3_bucket" "alert" {
  bucket        = "${var.bucket_prefix}-${var.player_number}"
  force_destroy = true
}

resource "aws_s3_object" "app" {
  bucket      = aws_s3_bucket.alert.id
  key         = "bin/app"
  source      = "${path.module}/../../provided/module4/app"
  source_hash = filemd5("${path.module}/../../provided/module4/app")
}
