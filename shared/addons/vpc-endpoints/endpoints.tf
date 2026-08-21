# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC Endpoint 부착 스니펫 — Gateway(s3·dynamodb) + Interface(PrivateLink)
# 원본: set-07 task-1 endpoints.tf, set-05 task-1 endpoints.tf(SG), set-08 task-1 vpc.tf(ddb)
# Gateway 라우트는 prefix-list 라 기존 0.0.0.0/0 라우트에 영향 없음.
# ---------------------------------------------------------------------------

data "aws_region" "addon_vpce" {}

resource "aws_vpc_endpoint" "addon_gateway" {
  for_each = toset(var.addon_vpce_gateway_services)

  vpc_id            = var.addon_vpce_vpc_id
  service_name      = "com.amazonaws.${data.aws_region.addon_vpce.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.addon_vpce_route_table_ids

  tags = { Name = "${var.addon_vpce_name_prefix}-${each.key}" }
}

# Interface Endpoint 는 ENI 로 들어오므로 443 만 VPC CIDR 에서 허용
resource "aws_security_group" "addon_vpce" {
  count = length(var.addon_vpce_interface_services) > 0 ? 1 : 0

  name        = var.addon_vpce_sg_name
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = var.addon_vpce_vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.addon_vpce_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = var.addon_vpce_sg_name }
}

resource "aws_vpc_endpoint" "addon_interface" {
  for_each = toset(var.addon_vpce_interface_services)

  vpc_id              = var.addon_vpce_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.addon_vpce.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.addon_vpce_subnet_ids
  security_group_ids  = [aws_security_group.addon_vpce[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.addon_vpce_name_prefix}-${each.key}" }
}
