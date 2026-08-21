# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# task-3 "신규 Lambda" 부착 스니펫 — VPC 내 Lambda → RDS Proxy(MySQL) 조회 + Function URL.
# ⚠ task-3 기본 규정은 Lambda 금지(mark 0-4 "부적절 사용 시 전체 0점"). 당일 과제지가 명시 허용할 때만.
# 원본: set-05 task-1 lambda.tf(vpc_config·ENI 인라인 권한), set-03 task-1 lambda.tf(Function URL),
#       task-3 rds-proxy.tf(Proxy·시크릿).
# pymysql 은 배포 전 `pip install pymysql -t lambda/` 로 zip 에 동봉한다 (precondition 이 검사).
# ---------------------------------------------------------------------------

data "archive_file" "addon_lamvpc" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/addon-lamvpc.zip"
  excludes    = ["**/__pycache__/**"]
}

resource "aws_cloudwatch_log_group" "addon_lamvpc" {
  name              = "/aws/lambda/${var.addon_lamvpc_function_name}"
  retention_in_days = var.addon_lamvpc_log_retention_days

  tags = { Name = var.addon_lamvpc_function_name }
}

resource "aws_security_group" "addon_lamvpc" {
  name        = "${var.addon_lamvpc_function_name}-sg"
  description = "Lambda ENI SG"
  vpc_id      = var.addon_lamvpc_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.addon_lamvpc_function_name}-sg" }
}

# DB SG 가 Lambda SG 를 허용해야 Proxy 에 닿는다 (task-3 db SG 는 이미 0.0.0.0/0 — 그땐 생략)
resource "aws_vpc_security_group_ingress_rule" "addon_lamvpc_db" {
  count = var.addon_lamvpc_db_sg_id != "" ? 1 : 0

  security_group_id            = var.addon_lamvpc_db_sg_id
  referenced_security_group_id = aws_security_group.addon_lamvpc.id
  from_port                    = var.addon_lamvpc_db_port
  to_port                      = var.addon_lamvpc_db_port
  ip_protocol                  = "tcp"
  description                  = "Lambda to RDS Proxy"
}

data "aws_iam_policy_document" "addon_lamvpc_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_lamvpc" {
  name               = "${var.addon_lamvpc_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.addon_lamvpc_assume.json
}

data "aws_iam_policy_document" "addon_lamvpc" {
  # ENI 는 리소스 수준 제한 미지원 → "*" (AWSLambdaVPCAccessExecutionRole 대신 인라인으로 최소화)
  statement {
    sid = "VpcEni"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "DbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.addon_lamvpc_secret_arn]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.addon_lamvpc.arn}:*"]
  }
}

resource "aws_iam_role_policy" "addon_lamvpc" {
  name   = "${var.addon_lamvpc_function_name}-policy"
  role   = aws_iam_role.addon_lamvpc.id
  policy = data.aws_iam_policy_document.addon_lamvpc.json
}

resource "aws_lambda_function" "addon_lamvpc" {
  function_name    = var.addon_lamvpc_function_name
  role             = aws_iam_role.addon_lamvpc.arn
  runtime          = var.addon_lamvpc_runtime
  handler          = "index.handler"
  filename         = data.archive_file.addon_lamvpc.output_path
  source_code_hash = data.archive_file.addon_lamvpc.output_base64sha256
  timeout          = 15

  vpc_config {
    subnet_ids         = var.addon_lamvpc_subnet_ids
    security_group_ids = [aws_security_group.addon_lamvpc.id]
  }

  environment {
    variables = {
      DB_HOST    = var.addon_lamvpc_proxy_endpoint
      DB_PORT    = tostring(var.addon_lamvpc_db_port)
      DB_NAME    = var.addon_lamvpc_db_name
      SECRET_ARN = var.addon_lamvpc_secret_arn
      TABLE      = var.addon_lamvpc_table
      KEY_COLUMN = var.addon_lamvpc_key_column
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.addon_lamvpc.name
  }

  lifecycle {
    precondition {
      condition     = fileexists("${path.module}/lambda/pymysql/__init__.py")
      error_message = "pymysql 의존성이 없습니다. 먼저 실행: pip install pymysql -t lambda/ (README 부착 절차 2)"
    }
  }

  depends_on = [aws_iam_role_policy.addon_lamvpc, aws_cloudwatch_log_group.addon_lamvpc]

  tags = { Name = var.addon_lamvpc_function_name }
}

resource "aws_lambda_function_url" "addon_lamvpc" {
  function_name      = aws_lambda_function.addon_lamvpc.function_name
  authorization_type = var.addon_lamvpc_url_auth_type
}

output "addon_lamvpc_function_url" {
  value = aws_lambda_function_url.addon_lamvpc.function_url
}
