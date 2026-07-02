output "cloudfront_domain_name" {
  description = "최종 사용자 엔드포인트"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "ecr_repository_url" {
  description = "docker tag/push 대상"
  value       = aws_ecr_repository.book.repository_url
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static.id
}

output "origin_verify_value" {
  description = "ALB 직접 검증용 헤더 값"
  value       = random_password.origin_verify.result
  sensitive   = true
}
