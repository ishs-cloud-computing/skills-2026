# ---------------------------------------------------------------------------
# Lambda (과제지 3. Lambda, lambda.md, mark 1-3)
# - 처리 함수: 이름 wsc2026-student-score-function (mark 1-3 채점 대상),
#   python3.12 / index.handler / env S3_BUCKET, DDB_TABLE 정확 일치 채점
# - 트리거 함수: S3 이벤트 → Step Functions StartExecution (lambda.md B)
# ---------------------------------------------------------------------------

# ----- 처리 함수 -----

data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/build/processor.zip"
}

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${var.processor_function_name}"
  retention_in_days = 30

  tags = { Name = var.processor_function_name }
}

resource "aws_lambda_function" "processor" {
  function_name    = var.processor_function_name
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "index.handler"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.score.id # mark 1-3
      DDB_TABLE = aws_dynamodb_table.score.name
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.processor.name
  }

  depends_on = [aws_iam_role_policy.lambda, aws_cloudwatch_log_group.processor]

  tags = { Name = var.processor_function_name }
}

# ----- 트리거 함수 -----

data "archive_file" "trigger" {
  type        = "zip"
  source_file = "${path.module}/lambda/trigger.py"
  output_path = "${path.module}/build/trigger.zip"
}

resource "aws_cloudwatch_log_group" "trigger" {
  name              = "/aws/lambda/${var.trigger_function_name}"
  retention_in_days = 30

  tags = { Name = var.trigger_function_name }
}

resource "aws_lambda_function" "trigger" {
  function_name    = var.trigger_function_name
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "trigger.handler"
  filename         = data.archive_file.trigger.output_path
  source_code_hash = data.archive_file.trigger.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      # State Machine ARN은 환경변수로 주입 (lambda.md 권장)
      STATE_MACHINE_ARN = aws_sfn_state_machine.workflow.arn
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.trigger.name
  }

  depends_on = [aws_iam_role_policy.lambda, aws_cloudwatch_log_group.trigger]

  tags = { Name = var.trigger_function_name }
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.trigger.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.score.arn
  source_account = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}
