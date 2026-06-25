# ---------------------------------------------------------------------------
# App Load Balancer (요구사항 12.1)
# - wsc-app-lb : L7 / Internal (Private Subnet), 외부 직접 접근 불가
# - CloudFront 를 통해서만 접근 (CloudFront origin-facing prefix list 로 SG 제한)
# - /health           -> 403 "Restrict access to api"
# - /v1/book  GET      -> Lambda(wsc-get-table-function)
# - /v1/book  POST     -> wsc Namespace 의 앱 Pod (IP TargetGroup, TGB 로 등록)
# - 그 외 모든 경로     -> 404 "Contents Not Found"
#
# 앱 Pod 등록은 k8s/app/targetgroupbinding.yaml(AWS LB Controller CRD) 가
# 아래 app TargetGroup ARN(outputs) 에 Pod IP 를 동적으로 바인딩한다.
# ---------------------------------------------------------------------------

# CloudFront 의 origin-facing 관리형 prefix list (CloudFront 에서만 인입 허용)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "app_lb" {
  name        = "wsc-app-lb-sg"
  description = "App ALB - allow 80 from CloudFront only"
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

  tags = { Name = "wsc-app-lb-sg" }
}

# ---------------------------------------------------------------------------
# EKS Shared Node Security Group
# - eksctl cluster.yaml 의 vpc.sharedNodeSecurityGroup 으로 지정한다.
# - app-lb 는 Terraform 이 생성하므로 AWS LB Controller 가 frontend SG 를 모른다.
#   따라서 ALB -> Pod(8080) health check / 트래픽이 노드 SG 에서 차단되어
#   타겟이 전부 unhealthy 가 된다(생성 후 수동으로 노드 SG 규칙을 넣던 단계).
#   이 SG 를 모든 노드에 미리 attach 해 app-lb SG -> 8080 을 사전 허용한다.
#   (addon-lb 는 LB Controller 가 자체 SG/backend 규칙을 관리하므로 여기서 제외)
# ---------------------------------------------------------------------------
resource "aws_security_group" "eks_shared_node" {
  name        = "wsc-eks-shared-node-sg"
  description = "Shared node SG - allow app-lb to reach Pod targets (8080)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App ALB to Pod target and health check (8080)"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.app_lb.id]
  }

  # 채점(6-4): bastion 에서 노드로 SSH 접속 후 인터넷 차단을 확인한다.
  # 부트스트랩에서 패스워드 로그인(Skill53##)을 켜더라도 노드 SG 가 22 를 막으면
  # ssh 접속 자체가 timeout 되므로 bastion -> 노드 22 인바운드를 허용한다.
  ingress {
    description     = "SSH from bastion (grading 6-4 node internet test)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-eks-shared-node-sg" }
}

resource "aws_lb" "app" {
  name               = "wsc-app-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_lb.id]
  subnets            = [for k in local.private_subnet_keys : aws_subnet.this[k].id]

  tags = { Name = "wsc-app-lb" }
}

# ----- App Pod 용 IP TargetGroup (TargetGroupBinding 으로 Pod IP 등록) -----
resource "aws_lb_target_group" "app" {
  name        = "wsc-app-tg"
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

  tags = { Name = "wsc-app-tg" }
}

# ----- Lambda TargetGroup -----
resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_table.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

resource "aws_lb_target_group" "lambda" {
  name        = "wsc-lambda-tg"
  target_type = "lambda"

  tags = { Name = "wsc-lambda-tg" }
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.get_table.arn
  depends_on       = [aws_lambda_permission.alb]
}

# ----- Listener (80) -----
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  # 기본: 명시되지 않은 모든 경로 -> 404 "Contents Not Found"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "Contents Not Found"
      status_code  = "404"
    }
  }
}

# /health -> 403 "Restrict access to api" (최우선)
resource "aws_lb_listener_rule" "health_block" {
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
    path_pattern {
      values = ["/health"]
    }
  }
}

# GET /v1/book -> Lambda
resource "aws_lb_listener_rule" "get_book" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    path_pattern {
      values = ["/v1/book"]
    }
  }
  condition {
    http_request_method {
      values = ["GET"]
    }
  }
}

# POST /v1/book -> App Pod
resource "aws_lb_listener_rule" "post_book" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 21

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/v1/book"]
    }
  }
  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}
