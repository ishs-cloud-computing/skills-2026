# ---------------------------------------------------------------------------
# Producer EC2 (과제지 4. EC2, Application.md — mark 4-5-B)
# - user_data 가 bootstrap_brokers_sasl_iam 을 참조 → MSK ACTIVE(~30분) 이후
#   생성되는 암묵 의존성. 부팅 시 토픽 생성이 첫 시도에 성공한다.
# - 토픽 생성(kafka CLI + IAM jar) → app 바이너리 S3 다운로드 → systemd 상시 실행
# ---------------------------------------------------------------------------

resource "aws_instance" "producer" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.producer_type
  subnet_id              = aws_subnet.this[var.producer_subnet_name].id
  vpc_security_group_ids = [aws_security_group.producer.id]
  iam_instance_profile   = aws_iam_instance_profile.producer.name

  # 토픽 생성 CLI 는 항상 IAM(9098). app(제공 바이너리)은 항상 tls(9094) — msk.tf 참고
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    region                = var.region
    bootstrap_servers_iam = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
    app_bootstrap_servers = aws_msk_cluster.this.bootstrap_brokers_tls
    kafka_version         = var.kafka_version
    msk_iam_auth_version  = var.msk_iam_auth_version
    raw_topic_name        = var.topic_raw.name
    raw_partitions        = var.topic_raw.partitions
    raw_rf                = var.topic_raw.replication_factor
    alert_topic_name      = var.topic_alert.name
    alert_partitions      = var.topic_alert.partitions
    alert_rf              = var.topic_alert.replication_factor
    app_bucket            = aws_s3_bucket.alert.id
    app_key               = aws_s3_object.app.key
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.producer_name }

  depends_on = [
    # user_data 의 kafka/java 다운로드·SSM 등록이 부팅 시 아웃바운드를 요구한다
    aws_nat_gateway.msk,
    aws_route.private_default,
    aws_s3_object.app,
  ]
}
