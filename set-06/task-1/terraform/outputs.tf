# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# eksctl envsubst / k8s envsubst / 런북 검증에 쓰는 값들 —
# `terraform output -json > outputs.json` 후 jq 로 추출 (README 런북)

output "account_id" {
  value = local.account_id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.main.id
}

output "ecr_url" {
  value = local.ecr_url
}

output "book_repo_url" {
  value = aws_ecr_repository.book.repository_url
}

output "book_tg_arn" {
  value = aws_lb_target_group.book.arn
}

output "grafana_tg_arn" {
  value = aws_lb_target_group.grafana.arn
}

output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "book_pod_sg_id" {
  value = aws_security_group.book_pod.id
}

output "node_shared_sg_id" {
  value = aws_security_group.node_shared.id
}

output "eks_kms_arn" {
  value = aws_kms_key.eks.arn
}

output "lambda_function_url" {
  value = aws_lambda_function_url.reservation.function_url
}

output "book_app_policy_arn" {
  value = aws_iam_policy.book_app.arn
}

output "grafana_policy_arn" {
  value = aws_iam_policy.grafana.arn
}

output "fluentbit_policy_arn" {
  value = aws_iam_policy.fluentbit.arn
}

output "lbc_policy_arn" {
  value = aws_iam_policy.lbc.arn
}

output "node_ptc_policy_arn" {
  value = aws_iam_policy.node_ptc.arn
}
