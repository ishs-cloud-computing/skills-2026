# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "automode_node_role_arn" {
  value = aws_iam_role.automode_node.arn
}

output "automode_node_role_name" {
  value = aws_iam_role.automode_node.name
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "tg_arns" {
  value = { for k, tg in aws_lb_target_group.app : k => tg.arn }
}

# 태그 포함 full URI — 빌드/푸시(STEP 4)와 k8s <IMAGE> 치환(STEP 8)이 같은 값을 쓴다.
output "ecr_image_uris" {
  value = { for k, repo in aws_ecr_repository.app : k => "${repo.repository_url}:${var.image_tag}" }
}

# 앱의 DB 접속 host (RDS 직결 대신 프록시)
output "db_proxy_endpoint" {
  value = aws_db_proxy.this.endpoint
}

# dump 적재용 직결 엔드포인트 (프록시 경유 적재는 세션 피닝 유발)
output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = local.db_port
}

output "alb_dns" {
  value = aws_lb.this.dns_name
}

# 채점 플랫폼 제출값: https://<cloudfront_domain>
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}
