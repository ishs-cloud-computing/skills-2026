output "alb_dns" {
  description = "ALB DNS (mark 2-3-B/2-5 curl 대상)"
  value       = aws_lb.analytics.dns_name
}

output "bastion_public_ip" {
  description = "Bastion 접속 IP (ec2-user / SSH 패스워드)"
  value       = aws_eip.bastion.public_ip
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
