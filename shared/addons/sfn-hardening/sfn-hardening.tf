# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Step Functions 강화 부착 스니펫 — 새 리소스만 여기. state machine 블록 안에 넣는
# logging_configuration·tracing_configuration 과 버킷 notification 의 eventbridge=true,
# SNS Publish / Map / Parallel ASL 은 README 블록과 statemachine/example.asl.json.
# 원본: set-02 task-2 module-1 stepfunctions.tf·iam.tf·s3.tf, module-3 sns.tf.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_sfnhard" {}
data "aws_region" "addon_sfnhard" {}

locals {
  # 리소스 참조 대신 ARN 조립 — SM → 역할 정책 → SM 순환을 끊는다 (set-02 m1 iam.tf 패턴)
  addon_sfnhard_sm_arn = "arn:aws:states:${data.aws_region.addon_sfnhard.region}:${data.aws_caller_identity.addon_sfnhard.account_id}:stateMachine:${var.addon_sfnhard_state_machine_name}"
}

# 로그 그룹 — logging_configuration.log_destination 에 ":*" 붙여 연결(README 블록)
resource "aws_cloudwatch_log_group" "addon_sfnhard" {
  name              = "/aws/vendedlogs/states/${var.addon_sfnhard_state_machine_name}"
  retention_in_days = var.addon_sfnhard_log_retention_days

  tags = { Name = var.addon_sfnhard_state_machine_name }
}

# 로그 전달(LogDelivery)·X-Ray·SNS — 기존 SFN 역할에 부착
data "aws_iam_policy_document" "addon_sfnhard" {
  # CloudWatch Logs 전달은 리소스 수준 제한 미지원 → "*"
  statement {
    sid = "LogDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutLogEvents",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
  statement {
    sid = "XRay"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]
    resources = ["*"]
  }
  dynamic "statement" {
    for_each = var.addon_sfnhard_sns_topic_arn != "" ? [1] : []
    content {
      sid       = "SnsPublish"
      actions   = ["sns:Publish"]
      resources = [var.addon_sfnhard_sns_topic_arn]
    }
  }
}

resource "aws_iam_role_policy" "addon_sfnhard" {
  name   = "${var.addon_sfnhard_state_machine_name}-hardening"
  role   = var.addon_sfnhard_role_name
  policy = data.aws_iam_policy_document.addon_sfnhard.json
}

# ----- S3 Object Created → EventBridge → StartExecution (bucket_name 비우면 생성 안 함) -----
# 버킷 쪽은 aws_s3_bucket_notification 에 eventbridge = true 가 있어야 이벤트가 온다(README 블록).
locals {
  addon_sfnhard_s3 = var.addon_sfnhard_s3_bucket_name != "" ? 1 : 0
}

resource "aws_cloudwatch_event_rule" "addon_sfnhard_s3" {
  count = local.addon_sfnhard_s3

  name = "${var.addon_sfnhard_state_machine_name}-s3-created"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = merge(
      { bucket = { name = [var.addon_sfnhard_s3_bucket_name] } },
      var.addon_sfnhard_s3_key_prefix != "" ? { object = { key = [{ prefix = var.addon_sfnhard_s3_key_prefix }] } } : {}
    )
  })

  tags = { Name = "${var.addon_sfnhard_state_machine_name}-s3-created" }
}

data "aws_iam_policy_document" "addon_sfnhard_events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_sfnhard_events" {
  count = local.addon_sfnhard_s3

  name               = "${var.addon_sfnhard_state_machine_name}-events-role"
  assume_role_policy = data.aws_iam_policy_document.addon_sfnhard_events_assume.json
}

data "aws_iam_policy_document" "addon_sfnhard_events" {
  statement {
    sid       = "StartExecution"
    actions   = ["states:StartExecution"]
    resources = [local.addon_sfnhard_sm_arn]
  }
}

resource "aws_iam_role_policy" "addon_sfnhard_events" {
  count = local.addon_sfnhard_s3

  name   = "${var.addon_sfnhard_state_machine_name}-events-policy"
  role   = aws_iam_role.addon_sfnhard_events[0].id
  policy = data.aws_iam_policy_document.addon_sfnhard_events.json
}

# 입력은 S3 이벤트 전체 — ASL 에서 $.detail.object.key / $.detail.bucket.name 으로 읽는다.
# 기존 ASL 이 $.key 를 기대하면 input_transformer 로 맞춘다(README 블록).
resource "aws_cloudwatch_event_target" "addon_sfnhard_s3" {
  count = local.addon_sfnhard_s3

  rule     = aws_cloudwatch_event_rule.addon_sfnhard_s3[0].name
  arn      = local.addon_sfnhard_sm_arn
  role_arn = aws_iam_role.addon_sfnhard_events[0].arn
}
