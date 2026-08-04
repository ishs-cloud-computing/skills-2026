# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC Flow Log (요구사항 3) → CloudWatch Logs (Platform CMK 암호화)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flowlog" {
  name              = "/unicorn/vpc/flowlog"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.platform.arn

  tags = { Name = "unicorn-vpc-flowlog" }
}

data "aws_iam_policy_document" "flowlog_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flowlog" {
  name               = "unicorn-vpc-flowlog-role"
  assume_role_policy = data.aws_iam_policy_document.flowlog_assume.json
}

data "aws_iam_policy_document" "flowlog" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flowlog.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flowlog" {
  name   = "unicorn-vpc-flowlog-policy"
  role   = aws_iam_role.flowlog.id
  policy = data.aws_iam_policy_document.flowlog.json
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flowlog.arn
  log_destination = aws_cloudwatch_log_group.flowlog.arn

  tags = { Name = "unicorn-vpc-flowlog" }
}
