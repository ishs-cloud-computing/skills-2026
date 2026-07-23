# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "account_id" {
  value = local.account_id
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_cidrs" {
  description = "eksctl extraCIDRs 용 (bastion -> private API 443 허용)"
  value       = [for k in local.public_subnet_keys : var.subnets[k].cidr]
}

output "private_subnet_ids" {
  description = "EKS NodeGroup / Karpenter 가 사용할 private 서브넷"
  value       = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "sqs_queue_url" {
  value = aws_sqs_queue.order.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.order.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "keda_policy_arn" {
  value = aws_iam_policy.keda.arn
}

output "app_sqs_policy_arn" {
  value = aws_iam_policy.app_sqs.arn
}

output "karpenter_controller_policy_arn" {
  value = aws_iam_policy.karpenter.arn
}

output "karpenter_node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}
