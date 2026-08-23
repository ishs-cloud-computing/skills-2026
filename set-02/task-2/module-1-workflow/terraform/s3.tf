# ---------------------------------------------------------------------------
# S3 (과제지 1. S3, mark 1-1)
# - wsc2026-student-score-bucket-<등번호>, input/ processed/ error/ 3개 prefix
# - 폴더 마커 객체를 만들지 않는다: 과제지가 "채점 시작시 버킷의 데이터가 삭제되어
#   있는지 확인" 을 요구해 0바이트 마커도 잔존 데이터로 잡힐 수 있다. 세 PRE 는
#   채점자가 올린 input/test.csv 와 워크플로우 산출물(processed/·error/)로 채워진다
#   — 워크플로우가 input 객체를 지우지 않는 이유다(statemachine/workflow.asl.json).
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "score" {
  bucket        = "${var.bucket_name_prefix}-${var.player_number}"
  force_destroy = true

  tags = { Name = "${var.bucket_name_prefix}-${var.player_number}" }
}

resource "aws_s3_bucket_public_access_block" "score" {
  bucket = aws_s3_bucket.score.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# input/*.csv 생성 시 트리거 Lambda 호출 (lambda.md B. 트리거 함수)
# suffix .csv 라서 Lambda 가 error/ 에 쓰는 json 으로는 재귀 트리거되지 않는다
resource "aws_s3_bucket_notification" "trigger" {
  bucket = aws_s3_bucket.score.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".csv"
  }

  # 권한이 먼저 생겨야 notification 등록이 성공한다 (없으면 간헐 apply 실패)
  depends_on = [aws_lambda_permission.s3_invoke]
}
