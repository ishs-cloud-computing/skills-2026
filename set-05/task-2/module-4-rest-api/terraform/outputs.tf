# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "region" {
  value = var.region
}

output "rest_api_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "invoke_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${var.region}.amazonaws.com/${var.stage_name}"
}

output "api_key_id" {
  description = "값 조회: aws apigateway get-api-keys --include-values"
  value       = aws_api_gateway_api_key.this.id
}

output "table_name" {
  value = aws_dynamodb_table.this.name
}
