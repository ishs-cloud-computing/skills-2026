# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda (요구사항 10)
# - wsc2026-book-get-function : GET /v1/book?booking_id= → DynamoDB GSI 조회
# - 코드/환경변수 at-rest 암호화: function CMK (kms_key_arn)
# - 환경변수 전송 중 암호화: TABLE_NAME 값 자체를 KMS 암호문으로 저장하고
#   (mark 7-1 이 get-function 출력에서 AQICAH... 암호문을 기대) 런타임에 복호화
# - Function URL(AWS_IAM) 을 CloudFront 별도 Origin 으로 연결 (요구사항 13)
# ---------------------------------------------------------------------------

data "archive_file" "book_get" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/build/book-get.zip"
}

resource "aws_cloudwatch_log_group" "book_function" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 7

  tags = { Name = var.lambda_function_name }
}

# TABLE_NAME 을 function CMK 로 암호화한 암호문 (state 에 고정 저장되어 재적용에도 불변)
resource "aws_kms_ciphertext" "table_name" {
  key_id    = aws_kms_key.function.key_id
  plaintext = aws_dynamodb_table.book.name
}

resource "aws_lambda_function" "book_get" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.book_function.arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.book_get.output_path
  source_code_hash = data.archive_file.book_get.output_base64sha256
  timeout          = 10
  # kms_key_arn = 환경변수 at-rest, source_kms_key_arn = 코드(zip) at-rest (요구사항 10 "람다 코드 암호화")
  kms_key_arn        = aws_kms_key.function.arn
  source_kms_key_arn = aws_kms_key.function.arn

  environment {
    variables = {
      TABLE_NAME = aws_kms_ciphertext.table_name.ciphertext_blob
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.book_function.name
  }

  depends_on = [aws_iam_role_policy_attachment.book_function, aws_cloudwatch_log_group.book_function]

  tags = { Name = var.lambda_function_name }
}

# CloudFront OAC(SigV4)로만 호출 가능하도록 AWS_IAM 인증
resource "aws_lambda_function_url" "book_get" {
  function_name      = aws_lambda_function.book_get.function_name
  authorization_type = "AWS_IAM"
}

# CloudFront 배포(OAC)가 Function URL 을 호출할 수 있게 허용 (2차 apply)
resource "aws_lambda_permission" "cloudfront" {
  count = var.enable_cdn ? 1 : 0

  statement_id           = "AllowCloudFrontInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.book_get.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.cdn[0].arn
  function_url_auth_type = "AWS_IAM"
}