# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# SNS (provided/module4/lambda.md — alert consumer 의 SNS_TOPIC_ARN, 이름 비채점)
resource "aws_sns_topic" "alert" {
  name = var.sns_topic_name
}
