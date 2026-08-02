# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# SNS Standard Topic (과제지 5-2, 채점 3-3). 구독자는 과제지 무요구 — 미생성.
resource "aws_sns_topic" "alert" {
  name = var.topic_name
  tags = { Name = var.topic_name }
}
