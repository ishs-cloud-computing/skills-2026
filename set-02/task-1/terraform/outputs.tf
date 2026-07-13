# eksctl cluster.yaml 렌더링(envsubst)과 k8s manifest 치환(sed)에 사용하는 값들.
# README 런북의 export 블록이 이 출력을 jq 로 읽는다.

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
  description = "EKS 클러스터/노드 배치 서브넷 (요구사항 8)"
  value       = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "public_subnet_ids" {
  value = { for k in local.public_subnet_keys : k => aws_subnet.this[k].id }
}

output "eks_kms_arn" {
  description = "eksctl secretsEncryption.keyARN (wskorea26-eks-key)"
  value       = aws_kms_key.eks.arn
}

output "cluster_extra_sg_id" {
  description = "eksctl vpc.securityGroup (CloudShell -> private API 443)"
  value       = aws_security_group.cluster_extra.id
}

output "node_sg_id" {
  description = "eksctl nodegroup securityGroups.attachIDs (ALB -> Pod)"
  value       = aws_security_group.node.id
}

output "environment_sg_id" {
  description = "채점용 CloudShell VPC Environment 에 지정할 SG (유의사항 13)"
  value       = aws_security_group.environment.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.book.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.web.id
}

output "app_target_group_arn" {
  description = "k8s TargetGroupBinding(wskorea26-book-tg) 대상"
  value       = aws_lb_target_group.book.arn
}

output "grafana_target_group_arn" {
  description = "k8s TargetGroupBinding(wskorea26-grafana-tg) 대상"
  value       = aws_lb_target_group.grafana.arn
}

output "book_alb_dns" {
  value = aws_lb.book.dns_name
}

output "grafana_alb_dns" {
  value = aws_lb.grafana.dns_name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

# eksctl iam.serviceAccounts.attachPolicyARNs 에 사용
output "book_app_policy_arn" {
  value = aws_iam_policy.book_app.arn
}

output "lbc_policy_arn" {
  value = aws_iam_policy.lbc.arn
}

output "fluent_bit_policy_arn" {
  value = aws_iam_policy.fluent_bit.arn
}
