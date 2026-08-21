# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda GET API 부착 스니펫 — DynamoDB 조회 함수 + 최소권한 역할 + 선생성 로그 그룹.
# 노출 방식은 (a) alb-lambda.tf / (b) README Function URL+CloudFront 블록 / (c) API GW 링크.
# 원본: set-07 task-1 lambda.tf (GetItem), set-03 task-1 lambda.tf (GSI Query).
# ---------------------------------------------------------------------------

data "archive_file" "addon_lamget" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/build/addon-lamget.zip"
}

resource "aws_cloudwatch_log_group" "addon_lamget" {
  name              = "/aws/lambda/${var.addon_lamget_function_name}"
  retention_in_days = var.addon_lamget_log_retention_days

  tags = { Name = var.addon_lamget_function_name }
}

data "aws_iam_policy_document" "addon_lamget_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_lamget" {
  name               = "${var.addon_lamget_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.addon_lamget_assume.json
}

data "aws_iam_policy_document" "addon_lamget" {
  statement {
    sid     = "DynamoRead"
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = [
      var.addon_lamget_table_arn,
      "${var.addon_lamget_table_arn}/index/*",
    ]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.addon_lamget.arn}:*"]
  }
  # 테이블이 SSE-KMS(CMK) 면 조회 시 복호화 권한이 없으면 AccessDenied
  dynamic "statement" {
    for_each = var.addon_lamget_table_kms_key_arn != "" ? [1] : []
    content {
      sid       = "TableCmkDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = [var.addon_lamget_table_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "addon_lamget" {
  name   = "${var.addon_lamget_function_name}-policy"
  role   = aws_iam_role.addon_lamget.id
  policy = data.aws_iam_policy_document.addon_lamget.json
}

resource "aws_lambda_function" "addon_lamget" {
  function_name    = var.addon_lamget_function_name
  role             = aws_iam_role.addon_lamget.arn
  runtime          = var.addon_lamget_runtime
  handler          = "index.handler"
  filename         = data.archive_file.addon_lamget.output_path
  source_code_hash = data.archive_file.addon_lamget.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = var.addon_lamget_table_name
      KEY_NAME   = var.addon_lamget_key_name
      INDEX_NAME = var.addon_lamget_index_name
      FIELDS     = join(",", var.addon_lamget_fields)
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.addon_lamget.name
  }

  depends_on = [aws_iam_role_policy.addon_lamget, aws_cloudwatch_log_group.addon_lamget]

  tags = { Name = var.addon_lamget_function_name }
}
