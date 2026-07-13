# ---------------------------------------------------------------------------
# IAM (과제지 6. IAM — 최소권한)
# - wsc2026-lambda-student-role: 과제가 Lambda 역할을 하나만 명명하므로
#   처리 함수(S3 get/put + DDB put)와 트리거 함수(StartExecution)가 공용
# - wsc2026-stepfunction-student-role: HeadObject/Copy/Delete + Lambda Invoke
# ---------------------------------------------------------------------------

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
  name               = var.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "ReadInputCsv"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.score.arn}/input/*"]
  }
  statement {
    sid       = "WriteErrorJson"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.score.arn}/error/*"]
  }
  statement {
    sid       = "SaveStudent"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.score.arn]
  }
  statement {
    sid     = "StartWorkflow"
    effect  = "Allow"
    actions = ["states:StartExecution"]
    # 리소스 참조 대신 ARN 조립: SM → 처리 Lambda → 이 정책 → SM 순환을 끊는다
    resources = ["arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.state_machine_name}"]
  }
  statement {
    sid     = "Logs"
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "${aws_cloudwatch_log_group.processor.arn}:*",
      "${aws_cloudwatch_log_group.trigger.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.lambda_role_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = var.sfn_role_name
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "sfn" {
  # HeadObject + CopyObject 소스 읽기
  statement {
    sid       = "ReadInput"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.score.arn}/input/*"]
  }
  # CopyObject 대상 쓰기 (processed/ 정상, error/ 실패)
  statement {
    sid     = "WriteMoved"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.score.arn}/processed/*",
      "${aws_s3_bucket.score.arn}/error/*",
    ]
  }
  statement {
    sid       = "DeleteInput"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${aws_s3_bucket.score.arn}/input/*"]
  }
  statement {
    sid       = "InvokeProcessor"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.processor.arn]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "${var.sfn_role_name}-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}
