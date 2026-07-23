# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# SQS (과제지 3. EKS Scaling - 1. SQS, 채점 3-1)
# - Standard Queue, 명시되지 않은 값은 기본값 사용 (과제지 명시)
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "order" {
  name = var.queue_name

  tags = { Name = var.queue_name }
}
