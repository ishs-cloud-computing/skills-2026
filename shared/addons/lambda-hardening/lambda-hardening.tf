# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda 강화 부착 스니펫 — 새 리소스만 여기. 함수 블록 안에 넣는 인자
# (tracing_config·dead_letter_config·reserved_concurrent_executions·kms_key_arn·
#  logging_config·vpc_config) 와 Function URL·ESM 옵션은 README 블록을 복사한다.
# 원본: set-07 task-1 lambda.tf(선생성 로그 그룹·CMK), set-05 task-1 lambda.tf(vpc_config).
# ---------------------------------------------------------------------------

# 선생성 로그 그룹 — Lambda 가 자동 생성하면 retention·CMK 를 못 건다.
# 함수 쪽 logging_config.log_group 으로 연결한다(README 블록).
resource "aws_cloudwatch_log_group" "addon_lamhard" {
  name              = "/aws/lambda/${var.addon_lamhard_function_name}"
  retention_in_days = var.addon_lamhard_log_retention_days
  kms_key_id        = var.addon_lamhard_log_kms_key_arn != "" ? var.addon_lamhard_log_kms_key_arn : null

  tags = { Name = var.addon_lamhard_function_name }
}

# ----- DLQ (과제지가 요구할 때만 — dlq_name 비우면 생성 안 함) -----
resource "aws_sqs_queue" "addon_lamhard_dlq" {
  count = var.addon_lamhard_dlq_name != "" ? 1 : 0

  name                      = var.addon_lamhard_dlq_name
  message_retention_seconds = 1209600

  tags = { Name = var.addon_lamhard_dlq_name }
}

# 비동기 호출 실패분은 Lambda 서비스가 함수 역할로 DLQ 에 넣는다 — SendMessage 없으면 조용히 유실.
data "aws_iam_policy_document" "addon_lamhard_dlq" {
  count = var.addon_lamhard_dlq_name != "" ? 1 : 0

  statement {
    sid       = "DlqSend"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.addon_lamhard_dlq[0].arn]
  }
}

resource "aws_iam_role_policy" "addon_lamhard_dlq" {
  count = var.addon_lamhard_dlq_name != "" ? 1 : 0

  name   = "${var.addon_lamhard_function_name}-dlq"
  role   = var.addon_lamhard_role_name
  policy = data.aws_iam_policy_document.addon_lamhard_dlq[0].json
}

# ----- 관리형 정책 (해당 인자를 붙일 때만 true) -----
resource "aws_iam_role_policy_attachment" "addon_lamhard_vpc" {
  count = var.addon_lamhard_enable_vpc_policy ? 1 : 0

  role       = var.addon_lamhard_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "addon_lamhard_xray" {
  count = var.addon_lamhard_enable_xray_policy ? 1 : 0

  role       = var.addon_lamhard_role_name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
