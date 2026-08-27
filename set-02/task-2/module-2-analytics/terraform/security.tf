# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Security Group
# - EC2 는 "Load Balancer 를 통해서만 외부 접근" (과제지 2. EC2)
#   → 앱 포트 인바운드는 ALB SG 에서만 허용
# - egress 전체 개방: 유의사항이 80/443 아웃바운드 개방을 허용하고,
#   SSM 에이전트·pip 설치가 NAT 경유 443 아웃바운드를 필요로 한다
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.alb_name}-sg"
  description = "ALB - allow HTTP 80 from anywhere"
  vpc_id      = aws_vpc.analytics.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.alb_name}-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.instance_name}-sg"
  description = "App EC2 - allow app port from ALB only"
  vpc_id      = aws_vpc.analytics.id

  ingress {
    description     = "App port from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.instance_name}-sg" }
}
