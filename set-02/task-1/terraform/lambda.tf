# ---------------------------------------------------------------------------
# Lambda (요구사항 9)
# - wskorea26-book-lambda : ALB GET 요청으로 예매 데이터 조회, Python 3.14 (mark 6-1)
# - 실행역할은 최소 권한: 테이블/GSI Query + 자체 로그 그룹 + 테이블 CMK 복호화
# - non-VPC (DynamoDB 퍼블릭 엔드포인트 사용 — 불필요 리소스 최소화)
# ---------------------------------------------------------------------------

data "archive_file" "book_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/build/book-lambda.zip"
}

resource "aws_cloudwatch_log_group" "book_lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 30

  tags = { Name = var.lambda_function_name }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "book_lambda" {
  name               = "${var.lambda_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "book_lambda" {
  statement {
    sid     = "DynamoQuery"
    effect  = "Allow"
    actions = ["dynamodb:Query"]
    resources = [
      aws_dynamodb_table.data.arn,
      "${aws_dynamodb_table.data.arn}/index/*",
    ]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.book_lambda.arn}:*"]
  }
  # 테이블이 wskorea26-dynamodb-key(SSE-KMS)로 암호화되어 있어 Query 시 복호화 필요
  statement {
    sid       = "TableCmkDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.dynamodb.arn]
  }
}

resource "aws_iam_role_policy" "book_lambda" {
  name   = "${var.lambda_function_name}-policy"
  role   = aws_iam_role.book_lambda.id
  policy = data.aws_iam_policy_document.book_lambda.json
}

resource "aws_lambda_function" "book" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.book_lambda.arn
  runtime          = var.lambda_runtime
  handler          = "index.handler"
  filename         = data.archive_file.book_lambda.output_path
  source_code_hash = data.archive_file.book_lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.data.name # mark 6-1
      INDEX_NAME = "concert_name-created_at-index"
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.book_lambda.name
  }

  depends_on = [aws_iam_role_policy.book_lambda, aws_cloudwatch_log_group.book_lambda]

  tags = { Name = var.lambda_function_name }
}
