# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# RDS Proxy (addon_rds_proxy_enabled). 원본: task-3 rds-proxy.tf.
# IAM 인증 REQUIRED 면 TLS 강제 — 클라이언트는 generate-db-auth-token + --ssl.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "addon_rds_proxy_assume" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_rds_proxy" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  name               = "${var.addon_rds_proxy_name}-role"
  assume_role_policy = data.aws_iam_policy_document.addon_rds_proxy_assume[0].json
}

data "aws_iam_policy_document" "addon_rds_proxy_secret" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.addon_rds.arn]
  }
}

resource "aws_iam_role_policy" "addon_rds_proxy_secret" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  name   = "${var.addon_rds_proxy_name}-secret"
  role   = aws_iam_role.addon_rds_proxy[0].id
  policy = data.aws_iam_policy_document.addon_rds_proxy_secret[0].json
}

resource "aws_db_proxy" "addon" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  # secret version·role policy 보다 먼저 뜨면 AUTH_FAILURE 로 대상이 UNAVAILABLE (task-3 실측)
  depends_on = [
    aws_secretsmanager_secret_version.addon_rds,
    aws_iam_role_policy.addon_rds_proxy_secret,
  ]

  name          = var.addon_rds_proxy_name
  engine_family = "MYSQL"
  role_arn      = aws_iam_role.addon_rds_proxy[0].arn

  vpc_subnet_ids         = [for s in aws_subnet.addon_rds_private : s.id]
  vpc_security_group_ids = [aws_security_group.addon_rds_proxy[0].id]
  require_tls            = var.addon_rds_proxy_iam_auth

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = var.addon_rds_proxy_iam_auth ? "REQUIRED" : "DISABLED"
    secret_arn  = aws_secretsmanager_secret.addon_rds.arn
    # MySQL 8.0 기본 caching_sha2_password 는 평문 연결에서 인증 실패 (task-3 실측)
    client_password_auth_type = "MYSQL_NATIVE_PASSWORD"
  }

  tags = { Name = var.addon_rds_proxy_name }
}

resource "aws_db_proxy_default_target_group" "addon" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  db_proxy_name = aws_db_proxy.addon[0].name

  connection_pool_config {
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "addon" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  db_proxy_name          = aws_db_proxy.addon[0].name
  target_group_name      = aws_db_proxy_default_target_group.addon[0].name
  db_instance_identifier = aws_db_instance.addon.identifier
}
