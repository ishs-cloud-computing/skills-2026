# ---------------------------------------------------------------------------
# Load Balancing (요구사항 9)
# - gj2026-alb : L7 / Internal (Private Subnet), 외부 직접 접근 불가 (채점 5-1)
# - CloudFront VPC Origin 을 통해서만 접근 (origin-facing prefix list 로 SG 제한)
# - POST /v1/*  -> book TargetGroup (gj2026-book-tg, Pod IP, TGB 로 등록)
# - /grafana*   -> grafana TargetGroup (gj2026-grafana-tg, Pod IP, TGB 로 등록)
# - 그 외       -> 404
# (GET /v1/book 등 POST 외 메서드는 CloudFront WAF 가 405 로 선차단 → ALB 미도달)
# ---------------------------------------------------------------------------

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "gj2026-alb-sg"
  description = "ALB - allow 80 from CloudFront only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from CloudFront edge only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj2026-alb-sg" }
}

# book Pod 전용 SG (Security Groups for Pods, k8s SecurityGroupPolicy 로 부여).
# ingress 8080 을 ALB SG 에서만 허용 → 클러스터 내 다른 Pod(nginx-test)는 차단(채점 4-5).
# strict enforcing mode 라 노드-로컬 트래픽도 이 SG 로 강제되므로 동일 노드라도 차단된다.
# kubelet probe 도 차단되므로 book Deployment 는 probe 대신 ALB TG health check 로 헬스 판정.
resource "aws_security_group" "book_pod" {
  name        = "gj2026-book-pod-sg"
  description = "book pod SG - allow 8080 from ALB only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "ALB to book pod (8080)"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj2026-book-pod-sg" }
}

# 노드 공용 SG. grafana Pod(애드온 노드, SGP 미적용)는 노드 ENI SG 로 통신하므로
# ALB SG -> grafana(3000) 인입을 여기서 허용한다. eksctl 각 nodegroup 에 attach.
resource "aws_security_group" "shared_node" {
  name        = "gj2026-eks-shared-node-sg"
  description = "Shared node SG - allow ALB to reach grafana pods (3000)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "ALB to grafana pod (3000)"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj2026-eks-shared-node-sg" }
}

resource "aws_lb" "this" {
  name               = "gj2026-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  tags = { Name = "gj2026-alb" }
}

resource "aws_lb_target_group" "book" {
  name        = "gj2026-book-tg"
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

  tags = { Name = "gj2026-book-tg" }
}

resource "aws_lb_target_group" "grafana" {
  name        = "gj2026-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/grafana/api/health"
    port                = "3000"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "gj2026-grafana-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "Contents Not Found"
      status_code  = "404"
    }
  }
}

# /grafana* -> grafana TG
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana", "/grafana/*"]
    }
  }
}

# POST /v1/* -> book Pod
resource "aws_lb_listener_rule" "post_book" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    path_pattern {
      values = ["/v1/*"]
    }
  }
  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}
