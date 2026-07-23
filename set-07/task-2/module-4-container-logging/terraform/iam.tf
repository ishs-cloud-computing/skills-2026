# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# IAM (유의사항 11: 최소 권한)
# - o11y-lbc-policy : AWS Load Balancer Controller 공식 IAM 정책
#   (iam/lbc-policy.json, 컨트롤러 v3.4.2 릴리스 문서 기준 — lbc-policy.version)
#   eksctl IRSA 가 kube-system/aws-load-balancer-controller SA 에 attach 한다.
# - EBS CSI 는 eksctl addon 의 wellKnownPolicies 가 역할을 만든다 (cluster.yaml).
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "lbc" {
  name   = "o11y-lbc-policy"
  policy = file("${path.module}/iam/lbc-policy.json")
}
