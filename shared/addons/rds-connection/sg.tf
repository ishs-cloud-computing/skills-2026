# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# SG 체인: 클라이언트 EC2 → (Proxy) → RDS, 전부 DB 포트만 SG 참조로 허용.
# CIDR 개방 없음 — "퍼블릭 차단" 채점은 publicly_accessible=false + 이 SG 가 담당.
# Proxy 가 없으면 DB SG 는 클라이언트 SG 만 허용한다.
# ---------------------------------------------------------------------------

resource "aws_security_group" "addon_rds_client" {
  name        = "${var.addon_rds_client_ec2_name}-sg"
  description = "rds client ec2"
  vpc_id      = aws_vpc.addon_rds.id
  tags        = { Name = "${var.addon_rds_client_ec2_name}-sg" }
}

resource "aws_vpc_security_group_egress_rule" "addon_rds_client_all" {
  security_group_id = aws_security_group.addon_rds_client.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "ssm, dnf, secrets manager"
}

resource "aws_security_group" "addon_rds_proxy" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  name        = "${var.addon_rds_proxy_name}-sg"
  description = "rds proxy"
  vpc_id      = aws_vpc.addon_rds.id
  tags        = { Name = "${var.addon_rds_proxy_name}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "addon_rds_proxy_from_client" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  security_group_id            = aws_security_group.addon_rds_proxy[0].id
  ip_protocol                  = "tcp"
  from_port                    = var.addon_rds_port
  to_port                      = var.addon_rds_port
  referenced_security_group_id = aws_security_group.addon_rds_client.id
  description                  = "db port from client"
}

resource "aws_vpc_security_group_egress_rule" "addon_rds_proxy_to_db" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  security_group_id            = aws_security_group.addon_rds_proxy[0].id
  ip_protocol                  = "tcp"
  from_port                    = var.addon_rds_port
  to_port                      = var.addon_rds_port
  referenced_security_group_id = aws_security_group.addon_rds_db.id
  description                  = "db port to rds"
}

resource "aws_security_group" "addon_rds_db" {
  name        = "${var.addon_rds_identifier}-sg"
  description = "rds instance"
  vpc_id      = aws_vpc.addon_rds.id
  tags        = { Name = "${var.addon_rds_identifier}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "addon_rds_db_from_client" {
  security_group_id            = aws_security_group.addon_rds_db.id
  ip_protocol                  = "tcp"
  from_port                    = var.addon_rds_port
  to_port                      = var.addon_rds_port
  referenced_security_group_id = aws_security_group.addon_rds_client.id
  description                  = "db port from client"
}

resource "aws_vpc_security_group_ingress_rule" "addon_rds_db_from_proxy" {
  count = var.addon_rds_proxy_enabled ? 1 : 0

  security_group_id            = aws_security_group.addon_rds_db.id
  ip_protocol                  = "tcp"
  from_port                    = var.addon_rds_port
  to_port                      = var.addon_rds_port
  referenced_security_group_id = aws_security_group.addon_rds_proxy[0].id
  description                  = "db port from proxy"
}
