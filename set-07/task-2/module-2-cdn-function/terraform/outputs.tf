# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "landing_url" {
  value = "https://${aws_cloudfront_distribution.ab.domain_name}/"
}

output "bucket_name" {
  value = aws_s3_bucket.landing.bucket
}
