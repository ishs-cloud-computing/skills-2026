# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "alb_dns" {
  description = "ALB DNS (mark 2-4/2-6 curl 대상)"
  value       = aws_lb.analytics.dns_name
}

output "app_instance_id" {
  description = "애플리케이션 EC2 인스턴스 ID (SSM 세션용)"
  value       = aws_instance.app.id
}

output "stream_name" {
  description = "Kinesis Data Stream 이름"
  value       = aws_kinesis_stream.orders.name
}

output "flink_app_name" {
  description = "Managed Flink Studio Notebook 이름"
  value       = var.flink_app_name
}

output "glue_db_name" {
  description = "Studio Notebook 카탈로그 Glue DB"
  value       = aws_glue_catalog_database.analytics.name
}
