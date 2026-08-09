# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "private_subnet_ids" {
  description = "eksctl/cluster.yaml의 vpc.subnets.private에 기입할 서브넷 id"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "eksctl/cluster.yaml의 vpc.subnets.public에 기입할 서브넷 id"
  value       = aws_subnet.public[*].id
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ecr_image_uris" {
  description = "태그 포함 full URI. 이미지 push와 k8s <IMAGE> 치환이 같은 값을 쓴다."
  value       = { for k, repo in aws_ecr_repository.app : k => "${repo.repository_url}:${var.image_tag}" }
}

output "db_proxy_endpoint" {
  description = "앱의 MYSQL_HOST. RDS 직결이 아니라 프록시다."
  value       = aws_db_proxy.this.endpoint
}

output "db_endpoint" {
  description = "dump 적재용 직결 엔드포인트. 프록시 경유 대량 적재는 세션 피닝을 유발한다."
  value       = aws_db_instance.this.address
}

output "db_port" {
  value = local.db_port
}

# depends_on이 필수다 — 변수만 참조하는 output은 어떤 리소스에도 의존하지 않아
# targeted apply에서 그래프가 잘릴 때 함께 잘려 state에 기록되지 않는다.
output "db_password" {
  description = "앱 매니페스트의 <DB_PASSWORD> 치환값"
  value       = var.db_password
  sensitive   = true
  depends_on  = [aws_db_instance.this]
}

output "alb_dns" {
  value = one(data.aws_lb.this[*].dns_name)
}

output "cloudfront_domain" {
  description = "채점 플랫폼 제출값: https://<이 도메인>"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "cloudfront_prefix_list_id" {
  description = "ALB를 CloudFront에서만 접근 가능하게 잠글 때 Ingress의 security-group-prefix-lists에 넣을 값"
  value       = data.aws_ec2_managed_prefix_list.cloudfront.id
}

output "waf_log_group" {
  description = "WAF 로그 그룹 (us-east-1). Logs Insights 대상."
  value       = aws_cloudwatch_log_group.waf.name
}
