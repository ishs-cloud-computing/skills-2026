# ---------------------------------------------------------------------------
# S3 (과제지 1. S3, mark 1-1)
# - wsc2026-student-score-bucket-<비번호>, input/ processed/ error/ 3개 prefix
# - 폴더 마커는 input/ 하나만 생성:
#   채점 시 processed/(test.csv)·error/(json 4개)에는 실제 객체가 있어 PRE 가 뜨고,
#   마커를 만들면 mark 1-5-A/B 목록에 잉여 0바이트 라인이 출력되어 오답 처리된다.
#   input/ 은 워크플로우가 파일을 옮겨가 비므로 마커가 있어야 PRE input/ 이 유지된다.
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

resource "aws_s3_object" "input_marker" {
  bucket  = aws_s3_bucket.score.id
  key     = "input/"
  content = ""
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
