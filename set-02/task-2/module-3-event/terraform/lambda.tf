# ---------------------------------------------------------------------------
# Lambda 6개 (provided/module3/lambda.md 4개 + mark2-3.sh 전용 2개)
# - 함수별 소스: lambda/<key>/index.py (provided 스켈레톤의 TODO 완성본)
# - Handler index.handler, Runtime python3.12 (mark 3-1 정확 일치)
# - 환경변수는 lambda.md 표와 정확 일치 (SNS_TOPIC_ARN 전체 공통)
# ---------------------------------------------------------------------------

locals {
  lambda_env = {
    sg_remediation       = { SECURITY_GROUP_ID = aws_security_group.event.id }
    role_remediation     = { INSTANCE_ID = aws_instance.event.id, ROLE_NAME = var.ec2_role_name }
    ec2_terminate_alert  = {}
    ec2_type_remediation = { INSTANCE_ID = aws_instance.event.id, INSTANCE_TYPE = var.instance_type }
    ec2_stop_remediation = { INSTANCE_ID = aws_instance.event.id }
    tag_alert            = {}
  }

  # stop/type 복구는 instance_stopped waiter 로 대기하므로 여유 타임아웃
  lambda_timeouts = {
    ec2_type_remediation = 300
    ec2_stop_remediation = 300
  }
}

data "archive_file" "lambda" {
  for_each = var.function_names

  type        = "zip"
  source_dir  = "${path.module}/lambda/${each.key}"
  output_path = "${path.module}/build/${each.key}.zip"
}

resource "aws_lambda_function" "this" {
  for_each = var.function_names

  function_name    = each.value
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "index.handler"
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256
  timeout          = lookup(local.lambda_timeouts, each.key, 60)

  environment {
    variables = merge(
      { SNS_TOPIC_ARN = aws_sns_topic.alert.arn },
      local.lambda_env[each.key],
    )
  }
}
