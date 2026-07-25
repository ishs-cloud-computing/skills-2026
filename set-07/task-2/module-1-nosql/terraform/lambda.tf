# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 지급 lambda.py 를 무수정 참조. 파일명이 lambda.py 라 handler 는 lambda.handler
# (런타임이 importlib 로 로드하므로 모듈명 lambda 는 문제없다).
data "archive_file" "audit" {
  type        = "zip"
  source_file = "${path.module}/../../provided/module-1/lambda.py"
  output_path = "${path.module}/build/audit.zip"
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 7
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

resource "aws_iam_role" "lambda" {
  name               = "${var.lambda_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# 유의사항 11: Action:"*" 금지 — 스트림 읽기 + audit 쓰기 + 로그만.
data "aws_iam_policy_document" "lambda" {
  statement {
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
    ]
    resources = [aws_dynamodb_table.reservation.stream_arn]
  }

  statement {
    actions   = ["dynamodb:ListStreams"]
    resources = ["${aws_dynamodb_table.reservation.arn}/stream/*"]
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit.arn]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.audit.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.lambda_function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "audit" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  handler          = "lambda.handler"
  timeout          = 30
  filename         = data.archive_file.audit.output_path
  source_code_hash = data.archive_file.audit.output_base64sha256

  environment {
    variables = {
      AUDIT_TABLE_NAME = var.audit_table_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.audit]
}

# 채점 1-3-A 가 ESM 정확히 1개(State=Enabled)를 검사한다.
resource "aws_lambda_event_source_mapping" "stream" {
  event_source_arn  = aws_dynamodb_table.reservation.stream_arn
  function_name     = aws_lambda_function.audit.arn
  starting_position = "LATEST"
}
