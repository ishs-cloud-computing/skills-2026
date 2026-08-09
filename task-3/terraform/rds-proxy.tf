# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_security_group" "db" {
  name        = local.db_sg_name
  description = "RDS and RDS Proxy"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "DB port"
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = local.db_sg_name }
}

resource "aws_secretsmanager_secret" "db" {
  name                    = local.db_secret_name
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = aws_db_instance.this.username
    password = var.db_password
  })
}

data "aws_iam_policy_document" "proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = local.db_proxy_role_name
  assume_role_policy = data.aws_iam_policy_document.proxy_assume.json
}

data "aws_iam_policy_document" "proxy_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_role_policy" "proxy_secret" {
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy_secret.json
}

resource "aws_db_proxy" "this" {
  # secret version은 그래프 리프라 README의 targeted apply에서 잘려 secret이 빈 채로 생성된다(실측).
  # 이 간선이 version을 targeted plan에 포함시킨다 — outputs.tf db_password와 같은 함정.
  depends_on = [aws_secretsmanager_secret_version.db]

  name          = local.db_proxy_name
  engine_family = contains(["mysql", "mariadb"], local.db_engine) ? "MYSQL" : "POSTGRESQL"
  role_arn      = aws_iam_role.proxy.arn

  vpc_subnet_ids         = aws_subnet.private[*].id
  vpc_security_group_ids = [aws_security_group.db.id]
  # 제공 앱은 수정 불가이고 TLS를 협상하지 않을 수 있다.
  require_tls = false

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db.arn
    # 앱이 non-TLS로 붙는데 MySQL 8.0 기본 caching_sha2_password는 평문 연결에서 인증이 실패한다.
    client_password_auth_type = contains(["mysql", "mariadb"], local.db_engine) ? "MYSQL_NATIVE_PASSWORD" : "POSTGRES_SCRAM_SHA_256"
  }
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = aws_db_instance.this.identifier
}
