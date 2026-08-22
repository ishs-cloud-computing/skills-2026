# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC Flow Log 부착 스니펫 — CloudWatch Logs 목적지
# 원본: set-07 task-1 flowlog.tf. S3 목적지 변형은 ./README.md 의 "블록" 절.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "addon_flowlog" {
  name              = var.addon_flowlog_log_group_name
  retention_in_days = var.addon_flowlog_retention_days
  # CMK 지정 시 key policy 에 logs 서비스 문장 필수 (kms/README 참고)
  kms_key_id = var.addon_flowlog_kms_key_arn != "" ? var.addon_flowlog_kms_key_arn : null

  tags = { Name = var.addon_flowlog_name }
}

data "aws_iam_policy_document" "addon_flowlog_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_flowlog" {
  name               = var.addon_flowlog_role_name
  assume_role_policy = data.aws_iam_policy_document.addon_flowlog_assume.json
}

data "aws_iam_policy_document" "addon_flowlog" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.addon_flowlog.arn}:*"]
  }
}

resource "aws_iam_role_policy" "addon_flowlog" {
  name   = "${var.addon_flowlog_role_name}-policy"
  role   = aws_iam_role.addon_flowlog.id
  policy = data.aws_iam_policy_document.addon_flowlog.json
}

resource "aws_flow_log" "addon" {
  vpc_id                   = var.addon_flowlog_vpc_id
  traffic_type             = var.addon_flowlog_traffic_type
  iam_role_arn             = aws_iam_role.addon_flowlog.arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.addon_flowlog.arn
  max_aggregation_interval = var.addon_flowlog_aggregation_interval

  tags = { Name = var.addon_flowlog_name }
}
