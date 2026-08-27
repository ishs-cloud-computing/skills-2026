# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda (과제지 6. Lambda 구성)
# - Name: wsc-rest-function, Runtime: Python 3.14
# - DynamoDB GetItem / PutItem(Conditional) 권한만 부여 (최소 권한)
# - Stack Trace 비노출, boto3 재사용 구조는 lambda/index.py 에서 처리
# ---------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/lambda.zip"
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
  name               = "${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_perms" {
  statement {
    sid       = "DynamoReadWrite"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.this.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_perms.json
}

resource "aws_lambda_function" "this" {
  function_name    = var.lambda_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.14"
  handler          = "index.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }

  tags = { Name = var.lambda_name }
}
