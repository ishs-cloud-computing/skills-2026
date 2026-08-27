# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 로그 그룹명은 과제 유의사항 18의 고정값 — 선수ID prefix 예외
resource "aws_cloudwatch_log_group" "app" {
  name              = var.log_group_name
  retention_in_days = 7

  tags = {
    Name = var.log_group_name
  }
}
