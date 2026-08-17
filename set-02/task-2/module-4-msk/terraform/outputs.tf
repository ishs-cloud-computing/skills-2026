output "cluster_arn" {
  description = "MSK 클러스터 ARN (mark 4-3/4-4)"
  value       = aws_msk_cluster.this.arn
}

output "bootstrap_brokers_sasl_iam" {
  description = "SASL/IAM 부트스트랩 브로커 (bastion kafka CLI 디버깅용)"
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "bootstrap_brokers_tls" {
  description = "비인증 TLS 부트스트랩 브로커 :9094 (제공 producer app 전용)"
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "alert_bucket" {
  description = "wsc2026-sensor-alert-bucket-<비번호> (mark 4-1)"
  value       = aws_s3_bucket.alert.id
}

# 런북이 버킷 이름을 직접 조립하는 자리가 여럿이라, 비번호를 사람이 다시 입력하지 않게 내보낸다
output "player_number" {
  description = "비번호 (런북 $NUM — 버킷 이름 접미사)"
  value       = var.player_number
}

output "producer_instance_id" {
  description = "wsc2026-sensor-producer 인스턴스 ID (SSM 접속용)"
  value       = aws_instance.producer.id
}

output "bastion_public_ip" {
  description = "Bastion 고정 IP (SSH: ec2-user + 패스워드)"
  value       = aws_eip.bastion.public_ip
}

# 아웃바운드 22 가 막힌 망에서 bastion 에 붙는 경로가 SSM 뿐이라 인스턴스 ID 가 필요하다
output "bastion_instance_id" {
  description = "Bastion 인스턴스 ID (SSM send-command·start-session 용)"
  value       = aws_instance.bastion.id
}

output "sns_topic_arn" {
  description = "alert consumer 가 발행하는 SNS Topic"
  value       = aws_sns_topic.alert.arn
}

# teardown 의 ENI 정리 스크립트가 이 값을 쓴다 — 태그 이름(var.vpc_name)으로 다시 찾으면
# 변수를 바꿨을 때 조용히 어긋날 수 있어 리소스 참조로 직접 낸다
output "vpc_id" {
  description = "msk-vpc VPC ID (teardown ENI 정리용)"
  value       = aws_vpc.msk.id
}
