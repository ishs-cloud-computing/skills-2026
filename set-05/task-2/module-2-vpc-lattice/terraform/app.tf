# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Application 서버 (과제지 4. VPC Lattice - Application 구성)
# - wsc-spoke-app-v1 / wsc-spoke-app-v2 : Spoke VPC Private Subnet AZ A 배치
# - 제공 배포파일(provided/2-2/version{1,2}.py)을 systemd 서비스로 TCP 8080 실행
#   (Flask 기반이므로 pip 로 flask 설치 후 실행, 배포파일은 수정하지 않음)
# ---------------------------------------------------------------------------

locals {
  app_servers = {
    "wsc-spoke-app-v1" = "version1.py"
    "wsc-spoke-app-v2" = "version2.py"
  }
}

resource "aws_security_group" "app" {
  name        = "wsc-spoke-app-sg"
  description = "App servers - allow 8080 from ALB"
  vpc_id      = aws_vpc.spoke.id

  ingress {
    description     = "App 8080 from ALB"
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

  tags = { Name = "wsc-spoke-app-sg" }
}

resource "aws_instance" "app" {
  for_each = local.app_servers

  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.this["wsc-spoke-sn-priv-a"].id
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = templatefile("${path.module}/app-userdata.sh.tftpl", {
    app_b64 = base64encode(file("${path.module}/../../provided/2-2/${each.value}"))
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = each.key }
}
