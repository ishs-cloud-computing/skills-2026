output "account_id" {
  value = local.account_id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "서브넷 이름 -> ID"
  value       = { for k in local.subnet_keys : k => aws_subnet.this[k].id }
}

output "subnet_ids_by_az" {
  description = "AZ -> 서브넷 ID (eksctl/리소스 배치용)"
  value       = { for k, v in var.subnets : v.az => aws_subnet.this[k].id }
}

output "eks_kms_key_arn" {
  description = "EKS Secret/EBS 암호화 CMK (eksctl secretsEncryption.keyARN)"
  value       = aws_kms_key.eks.arn
}

output "ecr_repository_url" {
  description = "book 리포지터리 URL"
  value       = aws_ecr_repository.book.repository_url
}

output "grafana_mirror_repo_url" {
  value = aws_ecr_repository.mirror_grafana.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static.id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.cdn.id
}

output "book_target_group_arn" {
  description = "k8s TargetGroupBinding(book-svc)이 Pod IP 를 등록할 대상"
  value       = aws_lb_target_group.book.arn
}

output "grafana_target_group_arn" {
  description = "k8s TargetGroupBinding(grafana)이 Pod IP 를 등록할 대상"
  value       = aws_lb_target_group.grafana.arn
}

output "shared_node_sg_id" {
  description = "eksctl 각 nodegroup 의 securityGroups.attachIDs 에 지정 (ALB->grafana 3000)"
  value       = aws_security_group.shared_node.id
}

output "book_pod_sg_id" {
  description = "k8s SecurityGroupPolicy 가 book Pod 에 부여할 SG (ALB->8080 만 허용)"
  value       = aws_security_group.book_pod.id
}

output "book_app_role_name" {
  description = "eksctl book SA 의 roleName 으로 고정 (DynamoDB 쓰기 제한 정책이 참조)"
  value       = local.book_app_role_name
}

output "lambda_function_url" {
  value = aws_lambda_function_url.reservation.function_url
}

output "iam_policy_arns" {
  description = "eksctl iamserviceaccount.attachPolicyARNs 에 사용"
  value = {
    book_app         = aws_iam_policy.book_app.arn
    fluentbit        = aws_iam_policy.fluentbit.arn
    grafana_cw       = aws_iam_policy.grafana_cw.arn
    ebs_csi          = aws_iam_policy.ebs_csi_kms.arn
    ecr_pull_through = aws_iam_policy.ecr_pull_through.arn
  }
}
