# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# SQS (과제지 3. EKS Scaling - 1. SQS, 채점 3-1)
# 과제지가 명시하지 않은 속성은 기본값을 그대로 둔다.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "order" {
  name = var.queue_name

  tags = { Name = var.queue_name }
}
