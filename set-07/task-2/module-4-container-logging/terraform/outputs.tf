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

output "node_extra_sg_id" {
  description = "ALB -> Pod(8080/3000) 인바운드 허용 SG (eksctl attachIDs)"
  value       = aws_security_group.node_extra.id
}

output "app_target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "grafana_target_group_arn" {
  value = aws_lb_target_group.grafana.arn
}

output "app_alb_dns" {
  description = "앱 ALB DNS (채점 4-4 curl 대상)"
  value       = aws_lb.app.dns_name
}

output "grafana_alb_dns" {
  description = "Grafana 접속 주소 (채점 4-6)"
  value       = aws_lb.grafana.dns_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "lbc_policy_arn" {
  value = aws_iam_policy.lbc.arn
}
