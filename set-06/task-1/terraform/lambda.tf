# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda (NOTES.md §3.8) — VPC 밖(엔드포인트 불필요), Function URL + CloudFront OAC
# - auth_type 은 AWS_IAM 이어야 OAC 서명 검증이 성립 (NONE 금지)
# ---------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda/index.zip"
}

resource "aws_lambda_function" "reservation" {
  function_name = "${var.name_prefix}-book-reservation"
  runtime       = var.lambda_runtime
  handler       = "index.handler"
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME       = aws_dynamodb_table.books.name
      GSI_NAME         = var.gsi_name
      METRIC_NAMESPACE = var.metric_namespace
    }
  }
}

resource "aws_lambda_function_url" "reservation" {
  function_name      = aws_lambda_function.reservation.function_name
  authorization_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cf_oac" {
  statement_id  = "AllowCloudFrontOAC"
  action        = "lambda:InvokeFunctionUrl"
  function_name = aws_lambda_function.reservation.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.main.arn
}

# 공식 문서가 InvokeFunctionUrl 과 함께 요구하는 두 번째 statement —
# 없으면 서명이 유효해도 generic Forbidden (실측 8-3 원인 후보)
resource "aws_lambda_permission" "cf_oac_invoke" {
  statement_id  = "AllowCloudFrontOACInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reservation.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.main.arn
}
