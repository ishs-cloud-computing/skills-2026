# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller 정책은 upstream 원본을 그대로 쓴다.
# 버전은 iam/lbc-policy.version 으로 고정한다. 직접 좁히면 ALB 생성이 조용히 실패하므로
# 유의사항 11(최소 권한)과의 관계는 NOTES.md 결정 로그를 따른다.
# EBS CSI 는 eksctl addon 의 wellKnownPolicies 가 역할을 만든다 (cluster.yaml).
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "lbc" {
  name   = "${var.name_prefix}-lbc-policy"
  policy = file("${path.module}/iam/lbc-policy.json")
}
