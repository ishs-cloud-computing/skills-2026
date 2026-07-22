# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# 앱 EC2 (과제지 1. NoSQL - 4. Application 배포, 채점 1-4/1-5)
# - t3.small + AL2023, Public IP, TCP 8080 오픈
# - 제공 app.py/requirements.txt 를 userdata 로 임베드해 systemd 서비스로 구동
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.ec2_name}-sg"
  description = "bigbae nosql app - allow 8080 from anywhere"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Flask app"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 유의사항 6: 80/443 Outbound Any open (전체 아웃바운드 허용에 포함)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.ec2_name}-sg" }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/ec2-userdata.sh.tftpl", {
    app_b64    = filebase64("${path.module}/../../provided/Module1-NoSQL/app.py")
    req_b64    = filebase64("${path.module}/../../provided/Module1-NoSQL/requirements.txt")
    aws_region = var.region
    table_name = var.reservation_table_name
    gsi_name   = var.gsi_name
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 강제
  }

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.ec2_name }
}
