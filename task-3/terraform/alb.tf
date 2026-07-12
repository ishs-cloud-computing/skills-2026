# ALB를 Terraform이 소유 → CloudFront 주소가 EKS 준비와 무관하게 확정된다.
# 파드 연결은 k8s TargetGroupBinding(Auto Mode 내장 컨트롤러)이 수행.

# internet-facing ALB. 퍼블릭 DNS는 생기지만 SG를 CloudFront 관리형 prefix list로
# 잠가 CloudFront만 접근 가능하다 → 실질 노출 없음, WAF 우회 경로 없음.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "skills-alb"
  description = "internet-facing ALB, HTTP from CloudFront only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from CloudFront"
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
    for_each = toset([for app in local.apps : app.port])
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
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "app" {
  for_each = local.apps

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
    "eks:eks-cluster-name" = local.cluster_name
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
  for_each = local.apps

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
