output "cluster_arn" {
  description = "MSK 클러스터 ARN (mark 4-3/4-4)"
  value       = aws_msk_cluster.this.arn
}

output "bootstrap_brokers_sasl_iam" {
  description = "SASL/IAM 부트스트랩 브로커 (bastion kafka CLI 디버깅용)"
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "alert_bucket" {
  description = "wsc2026-sensor-alert-bucket-<비번호> (mark 4-1)"
  value       = aws_s3_bucket.alert.id
}

output "producer_instance_id" {
  description = "wsc2026-sensor-producer 인스턴스 ID (SSM 접속용)"
  value       = aws_instance.producer.id
}

output "bastion_public_ip" {
  description = "Bastion 고정 IP (SSH: ec2-user + 패스워드)"
  value       = aws_eip.bastion.public_ip
}

output "sns_topic_arn" {
  description = "alert consumer 가 발행하는 SNS Topic"
  value       = aws_sns_topic.alert.arn
}
