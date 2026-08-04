# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Security Group 2개 (과제지 3-1)
# - client : in 8080 from 0.0.0.0/0 — 채점(mark2-1.sh)이 CloudShell 에서
#            Public IP 로 curl 하므로 개방 필요 (과제지가 외부 접근을 명시).
#            out all — pip 설치·CA bundle 다운로드·Secrets Manager API 호출용.
# - docdb  : in 27017 from client SG 만 — "외부 직접 노출 금지"(과제지 3-1)를
#            이 SG 가 담당. db 서브넷에 IGW 라우트도 없어 이중으로 차단.
# ---------------------------------------------------------------------------

resource "aws_security_group" "client" {
  name        = "${var.client_ec2_name}-sg"
  description = "nosql client app"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.client_ec2_name}-sg" }

  ingress {
    description = "client app from anywhere"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "docdb" {
  name        = "${var.docdb_cluster_identifier}-sg"
  description = "documentdb from client only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.docdb_cluster_identifier}-sg" }

  ingress {
    description     = "docdb from client sg only"
    from_port       = var.docdb_port
    to_port         = var.docdb_port
    protocol        = "tcp"
    security_groups = [aws_security_group.client.id]
  }
}
