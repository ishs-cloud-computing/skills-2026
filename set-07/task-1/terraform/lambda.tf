# ---------------------------------------------------------------------------
# Lambda (요구사항 9)
# - unicorn-get-booking-func : ALB GET 요청으로 예약 데이터 조회
# - Platform CMK 로 환경변수 암호화, 로그 그룹 /unicorn/lambda/get-booking
# - 실행역할: DynamoDB 조회 + Logs + KMS(Decrypt). non-VPC (NAT/Public 엔드포인트로 DynamoDB 접근)
# ---------------------------------------------------------------------------

data "archive_file" "get_booking" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/build/get-booking.zip"
}

# 로그 그룹 (Platform CMK)
resource "aws_cloudwatch_log_group" "get_booking" {
  name              = "/unicorn/lambda/get-booking"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform.arn

  tags = { Name = "unicorn-get-booking-func" }
}

# 실행 역할
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "get_booking" {
  name               = "unicorn-get-booking-func-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "get_booking" {
  statement {
    sid     = "DynamoRead"
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = [
      aws_dynamodb_table.concert.arn,
      "${aws_dynamodb_table.concert.arn}/index/*",
    ]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.get_booking.arn}:*"]
  }
  # 환경변수 복호화(Platform CMK) + DynamoDB App CMK 복호화
  statement {
    sid       = "Kms"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
    resources = [aws_kms_replica_key.platform.arn, aws_kms_key.app.arn]
  }
}

resource "aws_iam_role_policy" "get_booking" {
  name   = "unicorn-get-booking-func-policy"
  role   = aws_iam_role.get_booking.id
  policy = data.aws_iam_policy_document.get_booking.json
}

resource "aws_lambda_function" "get_booking" {
  function_name    = "unicorn-get-booking-func"
  role             = aws_iam_role.get_booking.arn
  runtime          = "python3.13"
  handler          = "index.handler"
  filename         = data.archive_file.get_booking.output_path
  source_code_hash = data.archive_file.get_booking.output_base64sha256
  timeout          = 10
  kms_key_arn      = aws_kms_replica_key.platform.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.concert.name
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.get_booking.name
  }

  depends_on = [aws_iam_role_policy.get_booking, aws_cloudwatch_log_group.get_booking]

  tags = { Name = "unicorn-get-booking-func" }
}
