output "instance_id" {
  description = "wsc2026-event-ec2 인스턴스 ID"
  value       = aws_instance.event.id
}

output "security_group_id" {
  description = "wsc2026-event-sg ID"
  value       = aws_security_group.event.id
}

output "sns_topic_arn" {
  description = "wsc2026-event-alert Topic ARN (mark 3-1)"
  value       = aws_sns_topic.alert.arn
}

output "logs_bucket" {
  description = "CloudTrail·Config 로그 버킷"
  value       = aws_s3_bucket.logs.id
}
