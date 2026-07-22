# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "app_public_ip" {
  description = "앱 EC2 Public IP (채점 1-4 curl 대상)"
  value       = aws_instance.app.public_ip
}

output "reservation_table_name" {
  value = aws_dynamodb_table.reservation.name
}

output "audit_table_name" {
  value = aws_dynamodb_table.audit.name
}

output "lambda_name" {
  value = aws_lambda_function.audit.function_name
}
