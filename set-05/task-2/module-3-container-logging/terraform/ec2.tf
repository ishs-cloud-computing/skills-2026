# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# App EC2 (과제지 5. Container Logging - EC2 Fluent Bit 및 애플리케이션 구성)
# - Name=wsc-log-app-bastion : Public Subnet AZ A, t3.small, AL2023
#   (채점 스크립트 mark3.sh 가 tag:Name=wsc-log-app-bastion 으로 조회하므로 정확히 일치시킴)
# - Docker 컨테이너 wsc-log-app (제공 Flask 앱, 5000, json-file, restart always)
# - Fluent Bit 호스트 설치(systemd) -> record_modifier -> Loki NLB:3100
# - SSM 권한 (채점 3-4 가 ssm send-command 사용)
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "wsc-logging-app-sg"
  description = "App EC2 - SSH + app 5000"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App 5000"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-logging-app-sg" }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "wsc-logging-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "wsc-logging-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.this["wsc-logging-sn-pub-a"].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/ec2-userdata.sh.tftpl", {
    app_py_b64       = base64encode(file("${path.module}/../../provided/2-3/app.py"))
    requirements_b64 = base64encode(file("${path.module}/../../provided/2-3/requirements.txt"))
    dockerfile_b64   = base64encode(file("${path.module}/../../provided/2-3/Dockerfile"))
    fluentbit_b64    = base64encode(file("${path.module}/../app/fluent-bit.conf"))
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "wsc-log-app-bastion" }
}
