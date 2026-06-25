# ---------------------------------------------------------------------------
# Internal ALB + Target Group (과제지 4. VPC Lattice - Load Balancer 구성)
# - wsc-spoke-app-alb : internal, Spoke Private Subnet
# - TG: wsc-spoke-v1-tg(app-v1), wsc-spoke-v2-tg(app-v2), HTTP 8080, health /healthcheck
# - Listener :80
#     /healthcheck                 -> 403 "Restrict access to api"
#     /version (header version=v1) -> wsc-spoke-v1-tg
#     /version (header version=v2) -> wsc-spoke-v2-tg
#     /version (헤더 없음)          -> v1 90% / v2 10% 가중
#     그 외                         -> 404 "Not Found"
# VPC Lattice 가 헤더로 버전을 결정한 뒤 ALB:80 으로 전달하면, ALB 가
# 보존된 version 헤더로 해당 App 으로 라우팅한다 (lattice.tf 참조).
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "wsc-spoke-app-alb-sg"
  description = "Internal ALB - allow 80 from VPC Lattice and spoke VPC"
  vpc_id      = aws_vpc.spoke.id

  ingress {
    description     = "HTTP from VPC Lattice managed prefix list"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.lattice.id]
  }

  ingress {
    description = "HTTP from spoke VPC (health/internal)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.spoke_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-spoke-app-alb-sg" }
}

resource "aws_lb" "app" {
  name               = "wsc-spoke-app-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for k in local.spoke_private_keys : aws_subnet.this[k].id]

  tags = { Name = "wsc-spoke-app-alb" }
}

resource "aws_lb_target_group" "v1" {
  name        = "wsc-spoke-v1-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.spoke.id

  health_check {
    path                = "/healthcheck"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "wsc-spoke-v1-tg" }
}

resource "aws_lb_target_group" "v2" {
  name        = "wsc-spoke-v2-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.spoke.id

  health_check {
    path                = "/healthcheck"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "wsc-spoke-v2-tg" }
}

resource "aws_lb_target_group_attachment" "v1" {
  target_group_arn = aws_lb_target_group.v1.arn
  target_id        = aws_instance.app["wsc-spoke-app-v1"].id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "v2" {
  target_group_arn = aws_lb_target_group.v2.arn
  target_id        = aws_instance.app["wsc-spoke-app-v2"].id
  port             = 8080
}

# ----- Listener :80 (default 404) -----
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# /healthcheck -> 403 (최우선)
resource "aws_lb_listener_rule" "healthcheck_block" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 10

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "Restrict access to api"
      status_code  = "403"
    }
  }

  condition {
    path_pattern { values = ["/healthcheck"] }
  }
}

# /version + header version=v1 -> v1-tg
resource "aws_lb_listener_rule" "version_v1" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.v1.arn
  }

  condition {
    path_pattern { values = ["/version"] }
  }
  condition {
    http_header {
      http_header_name = "version"
      values           = ["v1"]
    }
  }
}

# /version + header version=v2 -> v2-tg
resource "aws_lb_listener_rule" "version_v2" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.v2.arn
  }

  condition {
    path_pattern { values = ["/version"] }
  }
  condition {
    http_header {
      http_header_name = "version"
      values           = ["v2"]
    }
  }
}

# /version (헤더 없음) -> v1 90% / v2 10% 가중
resource "aws_lb_listener_rule" "version_weighted" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 40

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.v1.arn
        weight = 90
      }
      target_group {
        arn    = aws_lb_target_group.v2.arn
        weight = 10
      }
    }
  }

  condition {
    path_pattern { values = ["/version"] }
  }
}
