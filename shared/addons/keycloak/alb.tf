# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ALB HTTP 80 → EC2 8080. 원본: set-02 task-2 module-2 alb.tf.
# 헬스체크는 트래픽 포트의 /realms/master (200). 관리 포트 9000 /health/ready 를
# 쓰려면 health_check.port = "9000" + EC2 SG 에 ALB→9000 인바운드 추가.
# HTTPS 는 ACM 인증서가 있을 때만 — 443 리스너 블록은 README 참고.
# ---------------------------------------------------------------------------

resource "aws_security_group" "addon_kc_alb" {
  name        = "${var.addon_kc_alb_name}-sg"
  description = "Keycloak ALB - HTTP 80 from anywhere"
  vpc_id      = aws_vpc.addon_kc.id

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

  tags = { Name = "${var.addon_kc_alb_name}-sg" }
}

resource "aws_lb" "addon_kc" {
  name               = var.addon_kc_alb_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.addon_kc_alb.id]
  subnets            = [for s in aws_subnet.addon_kc_public : s.id]

  tags = { Name = var.addon_kc_alb_name }
}

resource "aws_lb_target_group" "addon_kc" {
  name     = var.addon_kc_tg_name
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.addon_kc.id

  health_check {
    path     = "/realms/master"
    matcher  = "200"
    interval = 30
  }

  tags = { Name = var.addon_kc_tg_name }
}

resource "aws_lb_target_group_attachment" "addon_kc" {
  target_group_arn = aws_lb_target_group.addon_kc.arn
  target_id        = aws_instance.addon_kc.id
  port             = 8080
}

resource "aws_lb_listener" "addon_kc_http" {
  load_balancer_arn = aws_lb.addon_kc.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.addon_kc.arn
  }
}
