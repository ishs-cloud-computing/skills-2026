# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ALB 2대 + TG 2개 (채점 4-2: 이름 정확 일치, active/application/internet-facing)
# - 채점이 TG 이름을 describe-target-groups --names 로 조회하므로 LBC Ingress 의
#   자동 생성 TG(k8s-… 랜덤명)를 쓸 수 없다 → Terraform 이 정확한 이름으로 생성,
#   pod IP 등록만 LBC TargetGroupBinding 이 담당 (k8s/30·40-tgb-*.yaml).
# - target_type ip: app-tg 는 pod 2개 → healthy 2, grafana-tg 는 pod 1개 → healthy 1
#   (채점 기대 출력과 target 수가 정확히 일치).
# - SG 는 두 ALB 공유 1개: TGB spec.networking 이 참조하는 소스 SG 를 단일화.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB ingress 80 from anywhere"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere (grading via ALB DNS)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# 선수 유의사항 6: 80/443 Outbound Any open
resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "to targets"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ----- ALB -----

resource "aws_lb" "app" {
  name               = var.app_alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for k in local.public_subnet_keys : aws_subnet.this[k].id]

  tags = { Name = var.app_alb_name }
}

resource "aws_lb" "grafana" {
  name               = var.grafana_alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for k in local.public_subnet_keys : aws_subnet.this[k].id]

  tags = { Name = var.grafana_alb_name }
}

# ----- Target Group (ip type — TGB 가 pod IP 등록) -----

resource "aws_lb_target_group" "app" {
  name        = var.app_tg_name
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = var.app_health_path
    matcher = "200"
  }

  tags = { Name = var.app_tg_name }
}

resource "aws_lb_target_group" "grafana" {
  name        = var.grafana_tg_name
  port        = var.grafana_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = var.grafana_health_path
    matcher = "200"
  }

  tags = { Name = var.grafana_tg_name }
}

# ----- Listener (HTTP 80 → TG) -----

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
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
