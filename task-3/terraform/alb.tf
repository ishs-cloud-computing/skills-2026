# 내부 ALB를 Terraform이 소유 → CloudFront 주소가 EKS 준비와 무관하게 확정된다.
# 파드 연결은 k8s TargetGroupBinding(Auto Mode 내장 컨트롤러)이 수행.

# CloudFront VPC Origin ENI → ALB:80. VPC Origin의 관리형 SG는 plan 시점에
# 참조할 수 없으므로 VPC CIDR로 허용한다 (내부 ALB라 외부 노출 없음).
resource "aws_security_group" "alb" {
  name        = "skills-alb"
  description = "internal ALB, HTTP from VPC (CloudFront VPC Origin)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from within VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "skills-alb" }
}

# 노드에 붙여 ALB→파드(앱 포트) 트래픽을 여는 SG.
# Auto Mode TGB는 spec.networking(SG 자동 개방)을 지원하지 않으므로
# NodeClass securityGroupSelectorTerms가 skills:alb-backend 태그로 이 SG를 선택한다.
resource "aws_security_group" "alb_backend" {
  name        = "skills-alb-backend"
  description = "allow ALB to reach pods on app ports"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = toset([for app in var.apps : app.port])
    content {
      description     = "app port from ALB"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                 = "skills-alb-backend"
    "skills:alb-backend" = "1"
  }
}

resource "aws_lb" "this" {
  name               = "skills-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.private[*].id
}

resource "aws_lb_target_group" "app" {
  for_each = var.apps

  name        = "skills-tg-${each.key}"
  vpc_id      = aws_vpc.this.id
  port        = each.value.port
  protocol    = "HTTP"
  target_type = "ip"

  # 파드 종료 시 빠른 드레인 (preStop sleep 15와 정합)
  deregistration_delay = 15

  health_check {
    path                = each.value.health_path
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "skills-tg-${each.key}"
    # Auto Mode 컨트롤러가 이 태그 없이는 타깃 등록 권한이 없다 (TGB 필수 조건)
    "eks:eks-cluster-name" = var.cluster_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # 제공 API 외 경로 → 404 (과제 요구)
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "app" {
  for_each = var.apps

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path, "${each.value.path}/*"]
    }
  }
}
