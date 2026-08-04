# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda (과제지 5-3, 채점 3-3·3-5) — 지급 remediate_security_group.py 무수정 참조.
# Runtime python3.12 는 과제지 명시값 (최신 안정 예외 조항보다 과제지 명시 우선).
# 로그 그룹은 선생성: 채점 3-5 가 /aws/lambda/<fn> 존재를 확인하고, 선생성으로
# retention 을 지정할 수 있다. 선존재 충돌 시 삭제 금지 — 이름 변수 리네임으로
# 우회 (NOTES 함정 절).
# ---------------------------------------------------------------------------

data "archive_file" "remediate" {
  type        = "zip"
  source_file = "${path.module}/../../provided/module-3/remediate_security_group.py"
  output_path = "${path.module}/build/remediate.zip"
}

resource "aws_cloudwatch_log_group" "remediate" {
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

# 과제지 5-3: SG 조회/수정 + SNS 발행 + Logs 기록만 (과도 권한 금지).
# Describe 는 리소스 수준 제한 미지원 → "*", Revoke 는 보호 SG 로 한정.
data "aws_iam_policy_document" "lambda" {
  statement {
    actions   = ["ec2:DescribeSecurityGroups"]
    resources = ["*"]
  }

  statement {
    actions   = ["ec2:RevokeSecurityGroupIngress"]
    resources = [aws_security_group.protected.arn]
  }

  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alert.arn]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.remediate.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.lambda_function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "remediate" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "remediate_security_group.lambda_handler"
  timeout          = var.lambda_timeout
  filename         = data.archive_file.remediate.output_path
  source_code_hash = data.archive_file.remediate.output_base64sha256

  environment {
    variables = {
      PROTECTED_SECURITY_GROUP_ID = aws_security_group.protected.id
      SNS_TOPIC_ARN               = aws_sns_topic.alert.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.remediate]

  tags = { Name = var.lambda_function_name }
}
