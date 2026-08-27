# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudWatch Log Groups (요구사항 12)
# - /wskorea26/eks/pod-logs : Fluent Bit 가 Pod 로그 전송 (auto_create_group=false)
# (Lambda 로그 그룹은 lambda.tf, EKS Control Plane 로그 그룹은 EKS 가 자동 생성)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "pod_logs" {
  name              = var.pod_log_group_name
  retention_in_days = 30

  tags = { Name = "wskorea26-pod-logs" }
}
