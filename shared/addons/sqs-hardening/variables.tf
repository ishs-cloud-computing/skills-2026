# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_sqs_dlq_name" {
  description = "DLQ 이름. 과제지 명시 이름과 정확히 일치. FIFO 소스 큐면 .fifo 로 끝나야 하고 fifo_queue = true 추가"
  type        = string
  default     = "skills-queue-dlq"
}

variable "addon_sqs_source_queue_arn" {
  description = "이 DLQ 로 보낼 기존 소스 큐 ARN (aws_sqs_queue.<기존>.arn). redrive allow policy 에 들어간다"
  type        = string
}

variable "addon_sqs_max_receive_count" {
  description = "소스 큐 redrive_policy 의 maxReceiveCount — 이 횟수만큼 수신 후 DLQ 로 이동 (README 블록에서 사용)"
  type        = number
  default     = 3
}

variable "addon_sqs_dlq_retention_seconds" {
  description = "DLQ 메시지 보존 (초). 소스 큐보다 길게 — 기본 14일 최대값"
  type        = number
  default     = 1209600
}

variable "addon_sqs_kms_key_id" {
  description = "SSE-KMS CMK ID/ARN/alias. 빈 문자열이면 SSE-SQS(sqs_managed_sse_enabled = true)"
  type        = string
  default     = ""
}

variable "addon_sqs_visibility_timeout_seconds" {
  description = "소스 큐 visibility timeout (초). Lambda 소비면 함수 timeout 의 6배 권장 (README 블록에서 사용)"
  type        = number
  default     = 30
}
