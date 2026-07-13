# ---------------------------------------------------------------------------
# ALB (요구사항 10 / 12)
# - wskorea26-book-alb (internet-facing, HTTP 80) :
#     기본 액션                              -> 403 Forbidden (CloudFront 미경유 차단, mark 7-2)
#     X-Origin-Verify=wskorea26-cf + POST    -> wskorea26-book-tg (Book App Pod)
#     X-Origin-Verify=wskorea26-cf (그 외)   -> wskorea26-lambda-tg (예매 조회)
#   * 규칙은 정확히 2개 유지 — mark 7-2 가 HttpHeaderConfig.Values[] 로
#     "wskorea26-cf" 2줄 출력을 검사한다. 규칙을 추가/삭제하지 말 것.
# - wskorea26-grafana-alb (internet-facing, HTTP 80) -> wskorea26-grafana-tg
# Pod 등록은 k8s TargetGroupBinding 이 수행한다.
# ---------------------------------------------------------------------------

# ===== wskorea26-book-alb =====
resource "aws_lb" "book" {
  name               = var.book_alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.book_alb.id]
  subnets            = local.public_subnet_ids

  tags = { Name = var.book_alb_name }
}

# Book App IP TargetGroup (TargetGroupBinding 으로 Pod IP 등록)
resource "aws_lb_target_group" "book" {
  name        = "wskorea26-book-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "wskorea26-book-tg" }
}

# Lambda TargetGroup
resource "aws_lb_target_group" "lambda" {
  name        = "wskorea26-lambda-tg"
  target_type = "lambda"

  tags = { Name = "wskorea26-lambda-tg" }
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.book.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.book.arn
  depends_on       = [aws_lambda_permission.alb]
}

# Listener 80: CloudFront 헤더 없는 요청은 모두 403 (요구사항 10)
resource "aws_lb_listener" "book" {
  load_balancer_arn = aws_lb.book.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

# CloudFront 경유 + POST -> Book App
# (CloudFront Function 이 POST /book 을 /v1/book 으로 재작성해 전달한다)
resource "aws_lb_listener_rule" "book_post" {
  listener_arn = aws_lb_listener.book.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }
  condition {
    http_header {
      http_header_name = var.origin_verify_header
      values           = [var.origin_verify_value]
    }
  }
  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}

# CloudFront 경유 나머지(GET 등) -> Lambda (예매 조회)
resource "aws_lb_listener_rule" "book_lambda" {
  listener_arn = aws_lb_listener.book.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }
  condition {
    http_header {
      http_header_name = var.origin_verify_header
      values           = [var.origin_verify_value]
    }
  }
}

# ===== wskorea26-grafana-alb =====
resource "aws_lb" "grafana" {
  name               = var.grafana_alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb.id]
  subnets            = local.public_subnet_ids

  tags = { Name = var.grafana_alb_name }
}

resource "aws_lb_target_group" "grafana" {
  name        = "wskorea26-grafana-tg"
  port        = var.grafana_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/api/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "wskorea26-grafana-tg" }
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
