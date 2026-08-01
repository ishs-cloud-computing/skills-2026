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

output "private_subnet_ids" {
  description = "EKS NodeGroup 이 사용할 private 서브넷"
  value       = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "alb_sg_id" {
  description = "TGB spec.networking 이 허용할 소스 SG (k8s 렌더 치환용)"
  value       = aws_security_group.alb.id
}

output "lbc_policy_arn" {
  value = aws_iam_policy.lbc.arn
}

output "app_alb_dns" {
  value = aws_lb.app.dns_name
}

output "grafana_alb_dns" {
  value = aws_lb.grafana.dns_name
}
