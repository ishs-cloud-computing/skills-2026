# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# SQS 하드닝 부착 스니펫 — DLQ + redrive allow policy
# 원본: set-08 task-2 module-4 sqs.tf (visibility_timeout 변수화). 기존 큐 안 인자
# (redrive_policy·SSE·visibility)는 ./README.md 블록으로 붙인다.
# ---------------------------------------------------------------------------

# SSE 는 sqs_managed_sse_enabled 와 kms_master_key_id 가 배타 — CMK 가 있으면 SSE-SQS 를 끈다.
resource "aws_sqs_queue" "addon_dlq" {
  name                      = var.addon_sqs_dlq_name
  message_retention_seconds = var.addon_sqs_dlq_retention_seconds

  sqs_managed_sse_enabled = var.addon_sqs_kms_key_id == "" ? true : null
  kms_master_key_id       = var.addon_sqs_kms_key_id == "" ? null : var.addon_sqs_kms_key_id

  tags = { Name = var.addon_sqs_dlq_name }
}

# 이 DLQ 를 쓸 수 있는 소스 큐를 제한 (byQueue, 최대 10개). 비우면 allowAll 이 기본이라 생략 가능.
resource "aws_sqs_queue_redrive_allow_policy" "addon_dlq" {
  queue_url = aws_sqs_queue.addon_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [var.addon_sqs_source_queue_arn]
  })
}
