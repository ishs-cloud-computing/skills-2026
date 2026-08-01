# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller IRSA 정책 (채점 4-2 간접 — TGB 로 pod IP 를 TG 에 등록)
# - files/lbc-iam-policy.json 은 kubernetes-sigs/aws-load-balancer-controller
#   v3.4.3 태그의 docs/install/iam_policy.json 원본 (수정 없음).
# - SA(aws-load-balancer-controller/kube-system)는 eksctl serviceAccounts 가
#   이 정책 ARN 을 붙여 생성한다 (cluster.yaml 참조).
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "lbc" {
  name   = var.lbc_policy_name
  policy = file("${path.module}/files/lbc-iam-policy.json")

  tags = { Name = var.lbc_policy_name }
}
