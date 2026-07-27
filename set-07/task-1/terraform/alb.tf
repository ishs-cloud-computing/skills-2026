# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Service Endpoint - ALB (요구사항 10-1, 12)
# - unicorn-alb (internal) : CloudFront(VPC Origin)에서만 접근. HTTP 80.
#     GET            -> Lambda(unicorn-get-booking-func)  [default]
#     POST           -> Book App(unicorn-tg)              [rule p20]
#     GET /health    -> Book App(unicorn-tg)              [rule p10]
# - unicorn-grafana-alb (internet-facing) : Grafana 외부 접근. unicorn-grafana-tg.
# Pod 등록은 k8s TargetGroupBinding 이 unicorn-tg / unicorn-grafana-tg 에 Pod IP 를 바인딩.
# ---------------------------------------------------------------------------

# ===== unicorn-alb (internal) =====
resource "aws_lb" "app" {
  name               = "unicorn-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.private_subnet_ids

  tags = { Name = "unicorn-alb" }
}

# Book App IP TargetGroup (TargetGroupBinding 으로 Pod IP 등록)
resource "aws_lb_target_group" "app" {
  name        = "unicorn-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/health"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "unicorn-tg" }
}

# Lambda TargetGroup
resource "aws_lb_target_group" "lambda" {
  name        = "unicorn-lambda-tg"
  target_type = "lambda"

  tags = { Name = "unicorn-lambda-tg" }
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_booking.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.get_booking.arn
  depends_on       = [aws_lambda_permission.alb]
}

# Listener 80: 기본은 GET -> Lambda
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }
}

# /health -> Book App (최우선)
resource "aws_lb_listener_rule" "health" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

# POST -> Book App
resource "aws_lb_listener_rule" "post" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}

# ===== unicorn-grafana-alb (internet-facing) =====
resource "aws_lb" "grafana" {
  name               = "unicorn-grafana-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb.id]
  subnets            = local.public_subnet_ids

  tags = { Name = "unicorn-grafana-alb" }
}

resource "aws_lb_target_group" "grafana" {
  name        = "unicorn-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/api/health"
    port                = "3000"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "unicorn-grafana-tg" }
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.grafana.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}
