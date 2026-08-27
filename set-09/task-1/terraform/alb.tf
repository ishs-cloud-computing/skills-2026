# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 80 포트 0.0.0.0/0 개방은 과제지 8장 보안그룹 표의 요구값.
# ALB 직접 접근 통제는 origin-verify 헤더 검증 listener rule이 담당.
resource "aws_security_group" "alb" {
  name        = local.alb_sg_name
  description = "ALB ingress from anywhere (CloudFront included)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere including CloudFront"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "To ECS tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.alb_sg_name
  }
}

resource "aws_lb" "this" {
  name               = local.alb_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = local.alb_name
  }
}

resource "aws_lb_target_group" "app" {
  name        = local.tg_name
  vpc_id      = aws_vpc.this.id
  target_type = "ip"
  protocol    = "HTTP"
  port        = var.container_port

  # interval 15 / threshold 2 — 대회 중 빠른 healthy 전환
  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = local.tg_name
  }
}

# Default rule: 헤더 없는 ALB 직접 접근은 403 — 과제 8장 "사용자는 ALB DNS 직접 호출 금지"
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      status_code  = "403"
      content_type = "text/plain"
      message_body = "Forbidden"
    }
  }
}

resource "aws_lb_listener_rule" "origin_verify" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = var.origin_verify_header
      values           = [random_password.origin_verify.result]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
