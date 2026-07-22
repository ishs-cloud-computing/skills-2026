# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# IAM (유의사항 11: 최소 권한)
# - Lambda: 예약 테이블 Stream 읽기 + 감사 테이블 PutItem + 기본 로그
# - EC2(앱): 예약 테이블 UpdateItem/Query (+GSI Query) + SSM 접속(디버깅)
# ---------------------------------------------------------------------------

# ----- Lambda -----
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
    sid       = "AuditWrite"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit.arn]
  }

  statement {
    sid = "StreamRead"
    actions = [
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:DescribeStream",
      "dynamodb:ListStreams",
    ]
    resources = [aws_dynamodb_table.reservation.stream_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.lambda_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_perms.json
}

# ----- EC2 (앱) -----
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.ec2_name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "app" {
  # app.py: reserve/cancel = UpdateItem(조건부), seats = Query(테이블),
  # my-bookings = Query(GSI) → 인덱스 ARN 포함
  statement {
    sid     = "ReservationReadWrite"
    actions = ["dynamodb:UpdateItem", "dynamodb:Query"]
    resources = [
      aws_dynamodb_table.reservation.arn,
      "${aws_dynamodb_table.reservation.arn}/index/${var.gsi_name}",
    ]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.ec2_name}-policy"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

# 디버깅용 SSM 접속 (인바운드 SSH 불필요)
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.ec2_name}-profile"
  role = aws_iam_role.app.name
}
