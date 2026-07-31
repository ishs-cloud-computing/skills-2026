# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# SQS (과제지 3-1)
# - 주문 큐. KEDA 가 메시지 수를 기준으로 order-processor Pod 를 스케일링한다.
# - Standard Queue, 명시되지 않은 값은 모두 기본값.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "order" {
  name = var.sqs_name

  tags = { Name = var.sqs_name }
}
