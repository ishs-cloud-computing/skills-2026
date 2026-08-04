# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# cluster.yaml·k8s manifest 치환(README 2·5단계)과 .env 작성이 소비한다.

output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "queue_url" {
  value = aws_sqs_queue.worker.url
}

output "queue_arn" {
  value = aws_sqs_queue.worker.arn
}

output "ecr_repo_url" {
  value = aws_ecr_repository.worker.repository_url
}

output "keda_policy_arn" {
  value = aws_iam_policy.keda.arn
}

output "worker_policy_arn" {
  value = aws_iam_policy.app_sqs.arn
}

output "karpenter_policy_arn" {
  value = aws_iam_policy.karpenter.arn
}

output "karpenter_node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "karpenter_node_role_arn" {
  value = aws_iam_role.karpenter_node.arn
}

output "account_id" {
  value = local.account_id
}
