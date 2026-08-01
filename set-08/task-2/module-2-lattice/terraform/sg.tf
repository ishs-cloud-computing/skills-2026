# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Security Group 3개 (과제지 4-2·4-3·4-4)
# - client   : in var.client_port from 0.0.0.0/0 (과제지 명시), out 은 Lattice
#              managed prefix list · var.listener_port(Lattice로 나가는
#              트래픽 포트) 만 — Lattice 도메인은 link-local 대역으로
#              해석되며 그 대역이 이 prefix list 에 들어있다.
#              DNS 는 VPC 리졸버 경유라 SG 평가 대상이 아니므로 별도 규칙 불필요.
# - service  : in 8080 from Lattice managed prefix list 만.
#              0.0.0.0/0 허용 시 채점 미충족 명시 (과제지 4-3) — Public IP
#              직접 접근 차단은 이 SG 가 담당한다.
# - sn_assoc : SN-VPC association 용. in 80 from Client VPC CIDR (과제지 4-4).
# ---------------------------------------------------------------------------

data "aws_ec2_managed_prefix_list" "vpc_lattice" {
  name = "com.amazonaws.${var.region}.vpc-lattice"
}

resource "aws_security_group" "client" {
  name        = "${var.client_ec2_name}-sg"
  description = "lattice client app"
  vpc_id      = aws_vpc.client.id
  tags        = { Name = "${var.client_ec2_name}-sg" }

  ingress {
    description = "client app from anywhere"
    from_port   = var.client_port
    to_port     = var.client_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "to vpc lattice data plane"
    from_port       = var.listener_port
    to_port         = var.listener_port
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id]
  }
}

resource "aws_security_group" "service" {
  name        = "${var.service_ec2_name}-sg"
  description = "lattice service app"
  vpc_id      = aws_vpc.service.id
  tags        = { Name = "${var.service_ec2_name}-sg" }

  ingress {
    description     = "service app from vpc lattice only"
    from_port       = var.service_port
    to_port         = var.service_port
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id]
  }
}

resource "aws_security_group" "sn_assoc" {
  name        = "${var.sn_name}-assoc-sg"
  description = "lattice sn vpc association"
  vpc_id      = aws_vpc.client.id
  tags        = { Name = "${var.sn_name}-assoc-sg" }

  ingress {
    description = "http from client vpc"
    from_port   = var.client_port
    to_port     = var.client_port
    protocol    = "tcp"
    cidr_blocks = [var.client_vpc_cidr]
  }
}
