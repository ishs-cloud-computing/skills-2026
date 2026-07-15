# S3 (과제지 7. S3 — mark 4-1 head-bucket): "오류 데이터 저장" 버킷.
# producer 바이너리는 EC2 부팅 다운로드용으로 bin/ 에 잠깐 올려두고, 채점 전에 제거한다
# (README 정리 단계 — EC2 는 /opt/app/app 에 캐시하므로 지워도 재부팅에 지장 없음).
# 별도 스테이징 버킷을 두지 않는 이유: 채점 무관 리소스를 남기지 않기 위함.
resource "aws_s3_bucket" "alert" {
  bucket        = "${var.bucket_prefix}-${var.player_number}"
  force_destroy = true
}

locals {
  # tls(기본): 제공 바이너리(9094). iam: 자체 IAM 바이너리(9098) — placeholder 경로.
  app_source = var.producer_auth_mode == "iam" ? "${path.module}/${var.iam_producer_binary_path}" : "${path.module}/../../provided/module4/app"
}

resource "aws_s3_object" "app" {
  bucket      = aws_s3_bucket.alert.id
  key         = "bin/app"
  source      = local.app_source
  source_hash = filemd5(local.app_source)
}
