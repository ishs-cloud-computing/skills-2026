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

# Task Role: 앱이 실제 호출하는 API만 (PutItem + CMK 사용 권한) — 최소 권한
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

  # CMK 암호화 테이블 접근 시 호출 주체에 KMS 권한 필요
  statement {
    sid = "KmsForDynamoDBCmk"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.ddb.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name   = "${var.name_prefix}-ecs-task-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task.json
}
