# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# terraform output -json > outputs.json 으로 내려 본 PC(eksctl 렌더)와
# VPC CloudShell(jq)에서 소비한다.

output "account_id" {
  value = local.account_id
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = { for k in local.public_subnet_keys : k => aws_subnet.this[k].id }
}

output "private_subnet_ids" {
  description = "EKS 노드 배치 서브넷 (eksctl cluster.yaml 에 주입)"
  value       = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "eks_kms_arn" {
  description = "eksctl secretsEncryption.keyARN"
  value       = aws_kms_key.eks.arn
}

output "db_kms_arn" {
  value = aws_kms_key.db.arn
}

output "ecr_kms_arn" {
  value = aws_kms_key.ecr.arn
}

output "bucket_kms_arn" {
  value = aws_kms_key.bucket.arn
}

output "function_kms_arn" {
  value = aws_kms_key.function.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.book.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static.id
}

output "table_name" {
  value = aws_dynamodb_table.book.name
}

output "lambda_function_url" {
  value = aws_lambda_function_url.book_get.function_url
}

output "cloudfront_domain" {
  value = var.enable_cdn ? aws_cloudfront_distribution.cdn[0].domain_name : null
}

output "eks_cp_extra_sg_id" {
  description = "eksctl vpc.securityGroup 에 지정 (mark-sg → private API 443)"
  value       = aws_security_group.eks_cp_extra.id
}

output "eks_shared_node_sg_id" {
  description = "eksctl nodegroup securityGroups.attachIDs 에 지정 (ALB → Pod 8080)"
  value       = aws_security_group.eks_shared_node.id
}

output "alb_sg_id" {
  description = "ingress 어노테이션 security-groups 에 지정"
  value       = aws_security_group.alb.id
}

output "mark_sg_id" {
  description = "채점용 CloudShell VPC Environment 에 지정할 SG"
  value       = aws_security_group.mark.id
}

# eksctl podIdentityAssociations.roleARN 에 사용
output "pod_identity_role_arns" {
  value = {
    book_pod  = aws_iam_role.book_pod.arn
    lbc       = aws_iam_role.lbc.arn
    fluentbit = aws_iam_role.fluentbit.arn
    grafana   = aws_iam_role.grafana.arn
  }
}

output "app_log_group" {
  description = "fluent-bit output 로그 그룹"
  value       = aws_cloudwatch_log_group.book_app.name
}

output "cluster_arn" {
  value = local.cluster_arn
}

# aws ssm start-session --target <이 값> (README step 4).
# enable_bastion=false 일 때도 output/destroy 가 깨지지 않도록 try 로 감싼다.
output "bastion_instance_id" {
  description = "작업용 bastion 인스턴스 ID (SSM 접속 대상)"
  value       = try(aws_instance.bastion[0].id, null)
}