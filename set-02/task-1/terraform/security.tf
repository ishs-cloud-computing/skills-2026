# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Security Groups
# - wskorea26-book-alb-sg      : 0.0.0.0/0 -> wskorea26-book-alb(80)
#                                (유의사항 6: ALB SG HTTP 80 Inbound Anyopen 허용.
#                                 CloudFront 외 접근 차단은 리스너 규칙의 X-Origin-Verify
#                                 헤더 검증 + 기본 403 이 담당 — mark 7-2)
# - wskorea26-grafana-alb-sg   : 0.0.0.0/0 -> wskorea26-grafana-alb(80) (요구사항 12)
# - wskorea26-node-sg          : ALB -> Pod(8080), grafana-alb -> Pod(3000).
#                                 노드에 직접 attach (eksctl securityGroups.attachIDs)
# - wskorea26-cluster-extra-sg : 채점 CloudShell -> EKS private API(443).
#                                 eksctl vpc.securityGroup 으로 control plane ENI 에 attach
# - wskorea26-vpc-environment-sg : 채점용 CloudShell VPC Environment SG (유의사항 13)
# 유의사항 6: 80/443 Outbound Anyopen — 전체 egress 허용으로 충족.
# ---------------------------------------------------------------------------

resource "aws_security_group" "book_alb" {
  name        = "wskorea26-book-alb-sg"
  description = "Book ALB - allow HTTP 80 from anywhere (CloudFront gate is the listener rule)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere"
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
  tags = { Name = "wskorea26-book-alb-sg" }
}

resource "aws_security_group" "grafana_alb" {
  name        = "wskorea26-grafana-alb-sg"
  description = "Grafana ALB - allow HTTP 80 from anywhere"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere (Grafana external access)"
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
  tags = { Name = "wskorea26-grafana-alb-sg" }
}

# 노드에 직접 attach 하는 공용 SG. Terraform 이 만든 ALB SG 를 LB Controller 가 모르므로
# ALB -> Pod target/health check 가 노드 SG 에서 막히지 않도록 사전 허용한다.
resource "aws_security_group" "node" {
  name        = "wskorea26-node-sg"
  description = "Shared node SG - allow ALBs to reach Pod targets (8080/3000)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "wskorea26-book-alb to Book App Pod"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.book_alb.id]
  }
  ingress {
    description     = "wskorea26-grafana-alb to Grafana Pod"
    from_port       = var.grafana_port
    to_port         = var.grafana_port
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wskorea26-node-sg" }
}

# 채점용 CloudShell VPC Environment 가 사용할 SG (유의사항 13).
# 채점 항목 0: priv-subnet-d + 이 SG 로 CloudShell 환경을 만들어 EKS 에 접근한다.
resource "aws_security_group" "environment" {
  name        = var.environment_sg_name
  description = "CloudShell VPC environment SG for marking"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = var.environment_sg_name }
}

# EKS Control Plane 추가 SG: cluster.yaml 의 vpc.securityGroup 으로 지정.
# CloudShell(environment SG)에서 private API(443)에 곧바로 접근 가능하게 한다.
resource "aws_security_group" "cluster_extra" {
  name        = "wskorea26-cluster-extra-sg"
  description = "Extra control plane SG - allow CloudShell environment to reach private API (443)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS to EKS API from CloudShell VPC environment"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.environment.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wskorea26-cluster-extra-sg" }
}
