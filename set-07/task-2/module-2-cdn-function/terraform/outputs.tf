# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "distribution_domain" {
  description = "배포 도메인 (채점 2-4/2-5 curl 대상)"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.landing.id
}

output "kvs_arn" {
  value = aws_cloudfront_key_value_store.ab_config.arn
}
