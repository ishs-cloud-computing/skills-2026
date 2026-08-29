# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ALB (NOTES.md §3.7) — internal, TG 2종뿐 (Lambda 용 3번째 TG 는 존재하지 않음 §0-1)
# - TG 는 Terraform 이 만들고 k8s TargetGroupBinding 이 바인딩만 수행
# - WAF 는 여기 붙이지 않는다 — CloudFront 엣지(CLOUDFRONT scope)에 연결
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "book" {
  name        = "${var.name_prefix}-book-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  # interval 5s(최소): 채점 10-1 은 로그그룹 삭제→DS 재시작→10초 POST 후 스트림 확인(약 13초 창).
  # 기본 30s 면 그 창 안에 한쪽 AZ ALB 노드의 health check 가 안 떠 스트림이 1개만 생길 수 있다(실측).
  # 5s 로 낮추면 양쪽 AZ 노드가 창 안에 여러 번 /health 를 쳐 두 스트림이 안정적으로 채워진다.
  health_check {
    path     = "/health"
    matcher  = "200"
    interval = 5
    timeout  = 2 # interval > timeout 제약 (기본 timeout 5 면 interval 5 거부됨)
  }
}

resource "aws_lb_target_group" "grafana" {
  name        = "${var.name_prefix}-grafana-tg"
  port        = var.grafana_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = "/grafana/api/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "book" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    path_pattern {
      values = ["/v1/book*"]
    }
  }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana*"]
    }
  }
}
