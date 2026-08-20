# ---------------------------------------------------------------------------
# ALB (과제지 3. Load Balancer, mark 2-2/2-3-B/2-5)
# - 리스너 HTTP 80, TG 포트 5000 (앱 포트) — mark 2-2 정확 일치
# - 헬스체크 /health (Application.md)
# ---------------------------------------------------------------------------

resource "aws_lb" "analytics" {
  name               = var.alb_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for name, s in var.subnets : aws_subnet.this[name].id if s.tier == "public"]

  tags = { Name = var.alb_name }
}

resource "aws_lb_target_group" "app" {
  name     = var.tg_name
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.analytics.id

  health_check {
    path    = "/health"
    matcher = "200"
  }

  tags = { Name = var.tg_name }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.analytics.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
