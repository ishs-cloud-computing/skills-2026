# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# RDS MySQL + Secrets Manager + 파라미터 그룹 + (선택) 이벤트 구독
# 원본: task-3 rds.tf·rds-proxy.tf, set-08 task-2 module-1 secrets.tf 범용화.
# 비밀번호는 random_password — 평문이 코드에 남지 않는다 (state 는 로컬+gitignore).
# ---------------------------------------------------------------------------

resource "random_password" "addon_rds" {
  length  = 24
  special = false # RDS 금지 문자(/ @ " 공백) 회피
}

resource "aws_secretsmanager_secret" "addon_rds" {
  name                    = var.addon_rds_secret_name
  recovery_window_in_days = 0 # teardown 후 같은 이름으로 즉시 재생성 가능해야 한다
}

resource "aws_secretsmanager_secret_version" "addon_rds" {
  secret_id = aws_secretsmanager_secret.addon_rds.id
  secret_string = jsonencode({
    username = var.addon_rds_username
    password = random_password.addon_rds.result
    host     = aws_db_instance.addon.address
    port     = var.addon_rds_port
    dbname   = var.addon_rds_db_name
  })
}

resource "aws_db_subnet_group" "addon_rds" {
  name       = "${var.addon_rds_identifier}-subnet-group"
  subnet_ids = [for s in aws_subnet.addon_rds_private : s.id]
  tags       = { Name = "${var.addon_rds_identifier}-subnet-group" }
}

resource "aws_db_parameter_group" "addon_rds" {
  name   = "${var.addon_rds_identifier}-pg"
  family = var.addon_rds_parameter_group_family

  dynamic "parameter" {
    for_each = var.addon_rds_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = { Name = "${var.addon_rds_identifier}-pg" }
}

resource "aws_db_instance" "addon" {
  identifier     = var.addon_rds_identifier
  engine         = "mysql"
  engine_version = var.addon_rds_engine_version
  instance_class = var.addon_rds_instance_class
  multi_az       = var.addon_rds_multi_az

  storage_type      = "gp3"
  allocated_storage = var.addon_rds_allocated_storage
  storage_encrypted = true # AWS 관리형 키. CMK 요구 시 kms_key_id 추가 (kms/ 키트)

  db_name  = var.addon_rds_db_name
  port     = var.addon_rds_port
  username = var.addon_rds_username
  password = random_password.addon_rds.result

  db_subnet_group_name   = aws_db_subnet_group.addon_rds.name
  vpc_security_group_ids = [aws_security_group.addon_rds_db.id]
  parameter_group_name   = aws_db_parameter_group.addon_rds.name
  publicly_accessible    = false

  backup_retention_period             = var.addon_rds_backup_retention_days
  deletion_protection                 = var.addon_rds_deletion_protection
  iam_database_authentication_enabled = var.addon_rds_iam_auth

  skip_final_snapshot = true
  apply_immediately   = true # 당일 변경이 유지보수 창까지 밀리지 않게

  tags = { Name = var.addon_rds_identifier }
}

# ----- RDS 이벤트 구독 (addon_rds_event_topic_name 이 비어 있으면 생성 안 함) -----
resource "aws_sns_topic" "addon_rds_event" {
  count = var.addon_rds_event_topic_name != "" ? 1 : 0

  name = var.addon_rds_event_topic_name
}

resource "aws_sns_topic_subscription" "addon_rds_event_email" {
  count = var.addon_rds_event_topic_name != "" && var.addon_rds_event_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.addon_rds_event[0].arn
  protocol  = "email"
  endpoint  = var.addon_rds_event_email
}

resource "aws_db_event_subscription" "addon_rds" {
  count = var.addon_rds_event_topic_name != "" ? 1 : 0

  name             = "${var.addon_rds_identifier}-events"
  sns_topic        = aws_sns_topic.addon_rds_event[0].arn
  source_type      = "db-instance"
  source_ids       = [aws_db_instance.addon.identifier]
  event_categories = var.addon_rds_event_categories
}
