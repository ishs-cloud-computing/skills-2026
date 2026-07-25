# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda (과제지 1. NoSQL - 3. Streams 처리 구성, 채점 1-3/1-6)
# 제공 lambda.py 를 수정 없이 패키징한다. zip 엔트리 이름이 lambda.py 이므로 handler 가
# lambda.handler 다 — 제공 파일명이 바뀌면 handler 도 같이 바꿔야 한다.
# ---------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../../provided/Module1-NoSQL/lambda.py"
  output_path = "${path.module}/build/lambda.zip"
}

resource "aws_lambda_function" "audit" {
  function_name    = var.lambda_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  handler          = "lambda.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      AUDIT_TABLE_NAME = aws_dynamodb_table.audit.name
    }
  }

  tags = { Name = var.lambda_name }
}

# 예약/취소 이벤트를 30초 내 적재해야 하므로(채점 1-6) 배칭 대기 없이 기본값 사용
resource "aws_lambda_event_source_mapping" "stream" {
  event_source_arn  = aws_dynamodb_table.reservation.stream_arn
  function_name     = aws_lambda_function.audit.arn
  starting_position = "LATEST"
}
