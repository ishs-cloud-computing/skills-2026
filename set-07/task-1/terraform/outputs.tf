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
  description = "EKS 노드/ALB(internal) 배치 서브넷"
  value       = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "public_subnet_ids" {
  value = { for k in local.public_subnet_keys : k => aws_subnet.this[k].id }
}

output "platform_kms_arn" {
  description = "Platform CMK replica(ap-northeast-2) — EKS secrets/EBS, k8s storageclass 에 사용"
  value       = aws_kms_replica_key.platform.arn
}

output "platform_kms_primary_arn" {
  description = "Platform CMK primary(us-east-1)"
  value       = aws_kms_key.platform_primary.arn
}

output "app_kms_arn" {
  value = aws_kms_key.app.arn
}

output "data_kms_arn" {
  value = aws_kms_key.data.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.web.id
}

output "app_target_group_arn" {
  description = "k8s TargetGroupBinding(unicorn-tg) 대상"
  value       = aws_lb_target_group.app.arn
}

output "grafana_target_group_arn" {
  description = "k8s TargetGroupBinding(unicorn-grafana-tg) 대상"
  value       = aws_lb_target_group.grafana.arn
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "grafana_alb_dns_name" {
  value = aws_lb.grafana.dns_name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "eks_cp_extra_sg_id" {
  description = "eksctl vpc.securityGroup 에 지정 (unicorn-mark -> private API 443)"
  value       = aws_security_group.eks_cp_extra.id
}

output "eks_shared_node_sg_id" {
  description = "eksctl nodegroup securityGroups.attachIDs 에 지정 (ALB -> Pod)"
  value       = aws_security_group.eks_shared_node.id
}

output "mark_sg_id" {
  description = "채점용 CloudShell VPC Environment(unicorn-mark) 에 지정할 SG"
  value       = aws_security_group.mark.id
}

# eksctl podIdentityAssociations.roleARN 에 사용
output "pod_identity_role_arns" {
  value = {
    book_app   = aws_iam_role.book_app.arn
    fluentbit  = aws_iam_role.fluentbit.arn
    cwexporter = aws_iam_role.cwexporter.arn
    lbc        = aws_iam_role.lbc.arn
    ebs_csi    = aws_iam_role.ebs_csi.arn
  }
}

output "cluster_arn" {
  value = local.cluster_arn
}
