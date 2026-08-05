# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# SQS Standard 큐 (과제지 6-3, 채점 4-2 가 QueueArn·VisibilityTimeout 확인)
resource "aws_sqs_queue" "worker" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout
}
