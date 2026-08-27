# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution Role: ECR pull + CloudWatch Logs push (인프라 계층)
resource "aws_iam_role" "ecs_execution" {
  name               = local.execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = local.execution_role_name
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role: 앱이 실제 호출하는 API만 (PutItem) — 최소 권한 (과제 7.3)
resource "aws_iam_role" "ecs_task" {
  name               = local.task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = local.task_role_name
  }
}

data "aws_iam_policy_document" "ecs_task" {
  statement {
    sid       = "DynamoDBPutItem"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.booking.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name   = "${var.player_number}-ecs-task-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task.json
}
