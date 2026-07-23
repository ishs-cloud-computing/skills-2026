# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ALB / Target Group (과제지 4-2/4-5, 채점 4-2)
# - 채점이 ALB·TG 를 "이름"으로 조회하므로 LBC Ingress(이름 지정 불가) 대신
#   Terraform 으로 이름을 정확히 만들고, Pod 등록은 k8s TargetGroupBinding 이 한다.
# - o11y-app-alb -> o11y-app-tg (8080, /healthz)
# - o11y-grafana-alb -> o11y-grafana-tg (3000, /api/health)
# ---------------------------------------------------------------------------

# ----- ALB SG: 80 인바운드 오픈 -----
resource "aws_security_group" "alb" {
  name        = "o11y-alb-sg"
  description = "o11y ALBs - allow HTTP from anywhere"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "o11y-alb-sg" }
}

# ----- 노드 추가 SG: ALB -> Pod(8080/3000) 인바운드 허용 -----
# eksctl NodeGroup 의 securityGroups.attachIDs 로 노드에 부착한다 (cluster.yaml).
resource "aws_security_group" "node_extra" {
  name        = "o11y-node-extra-sg"
  description = "Allow ALB to reach app(8080) and grafana(3000) pods"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "app from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "grafana from ALB"
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

  tags = { Name = "o11y-node-extra-sg" }
}

# ===== o11y-app-alb =====
resource "aws_lb" "app" {
  name               = var.app_alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  tags = { Name = var.app_alb_name }
}

resource "aws_lb_target_group" "app" {
  name        = var.app_tg_name
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/healthz"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = var.app_tg_name }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ===== o11y-grafana-alb =====
resource "aws_lb" "grafana" {
  name               = var.grafana_alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  tags = { Name = var.grafana_alb_name }
}

resource "aws_lb_target_group" "grafana" {
  name        = var.grafana_tg_name
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

  tags = { Name = var.grafana_tg_name }
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
