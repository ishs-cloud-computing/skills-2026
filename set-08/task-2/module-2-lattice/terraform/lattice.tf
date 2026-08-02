# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC Lattice (과제지 4-4). 채점 2-3·2-4 가 name 필드 정확 일치로 조회하므로
# 리소스 name = 과제지 값. auth 는 과제지 무요구 → NONE.
# SN-VPC association 은 Client VPC 만 (소비 측만 연결 필요 — target 은
# TG 의 vpc_identifier 로 직접 도달).
# ---------------------------------------------------------------------------

resource "aws_vpclattice_service_network" "this" {
  name      = var.sn_name
  auth_type = "NONE"
  tags      = { Name = var.sn_name }
}

resource "aws_vpclattice_service_network_vpc_association" "client" {
  vpc_identifier             = aws_vpc.client.id
  service_network_identifier = aws_vpclattice_service_network.this.id
  security_group_ids         = [aws_security_group.sn_assoc.id]
}

resource "aws_vpclattice_service" "order" {
  name      = var.lattice_service_name
  auth_type = "NONE"
  tags      = { Name = var.lattice_service_name }
}

resource "aws_vpclattice_service_network_service_association" "order" {
  service_identifier         = aws_vpclattice_service.order.id
  service_network_identifier = aws_vpclattice_service_network.this.id
}

resource "aws_vpclattice_target_group" "order" {
  name = var.tg_name
  type = "INSTANCE"
  tags = { Name = var.tg_name }

  config {
    vpc_identifier = aws_vpc.service.id
    port           = var.service_port
    protocol       = "HTTP"

    health_check {
      enabled  = true
      path     = "/health"
      protocol = "HTTP"
      port     = var.service_port
    }
  }
}

resource "aws_vpclattice_target_group_attachment" "service" {
  target_group_identifier = aws_vpclattice_target_group.order.id

  target {
    id   = aws_instance.service.id
    port = var.service_port
  }
}

resource "aws_vpclattice_listener" "http" {
  name               = var.listener_name
  protocol           = "HTTP"
  port               = var.listener_port
  service_identifier = aws_vpclattice_service.order.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.order.id
        weight                  = 100
      }
    }
  }
}
