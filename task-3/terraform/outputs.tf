# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

# 태그 포함 full URI — 빌드/푸시와 k8s <IMAGE> 치환이 같은 값을 쓴다.
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

# 앱 매니페스트의 <DB_PASSWORD> 치환값 (README STEP 6).
# depends_on이 필수다 — 변수만 참조하는 output은 어떤 리소스에도 의존하지 않아
# STEP 1의 targeted apply에서 그래프가 잘릴 때 함께 잘려 state에 기록되지 않는다.
# 이 output이 없으면 STEP 6에서 `terraform output -raw db_password`가 빈 값을 낸다.
output "db_password" {
  value      = var.db_password
  sensitive  = true
  depends_on = [aws_db_instance.this]
}

# LBC가 Ingress로부터 만든 ALB. CloudFront origin과 동일한 조회 결과다.
output "alb_dns" {
  value = data.aws_lb.this.dns_name
}

# 채점 플랫폼 제출값: https://<cloudfront_domain>
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

# k8s/20-ingress.yaml의 security-group-prefix-lists 주석을 해제할 때 쓸 값
# (ALB를 CloudFront에서만 접근 가능하게 잠그는 선택 사항)
output "cloudfront_prefix_list_id" {
  value = data.aws_ec2_managed_prefix_list.cloudfront.id
}
