# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Client EC2 instance profile — 지급 앱이 boto3 로 Secret 을 읽는다.
# GetSecretValue 를 해당 Secret 하나로 한정 (과도 권한 금지).
# Secret 암호화 키는 AWS 관리형(aws/secretsmanager) — 별도 kms 권한 불필요.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "client" {
  name               = "${var.client_ec2_name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "client" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.docdb.arn]
  }
}

resource "aws_iam_role_policy" "client" {
  name   = "${var.client_ec2_name}-policy"
  role   = aws_iam_role.client.id
  policy = data.aws_iam_policy_document.client.json
}

resource "aws_iam_instance_profile" "client" {
  name = "${var.client_ec2_name}-profile"
  role = aws_iam_role.client.name
}
