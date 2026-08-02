# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# mark2-3.sh 가 조회하는 값과 동일 형태 — 배포 후 즉시 자가 검증용.

output "protected_sg_id" {
  value = aws_security_group.protected.id
}

output "topic_arn" {
  value = aws_sns_topic.alert.arn
}

output "lambda_arn" {
  value = aws_lambda_function.remediate.arn
}

output "trail_bucket" {
  value = aws_s3_bucket.trail.id
}
