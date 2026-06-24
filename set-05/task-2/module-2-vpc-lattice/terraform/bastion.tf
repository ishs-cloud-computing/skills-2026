# ---------------------------------------------------------------------------
# Bastion (과제지 4. VPC Lattice - Bastion 구성)
# - Hub VPC Public Subnet AZ A 배치, EIP 로 재시작 시에도 IP 고정
# - SSH Password 방식 (Skill53##)
# - mark2.sh(VPC Lattice 채점)를 이 Bastion 에서 수행하므로 Admin 권한 + curl/jq 설치
# - Tag: Name=wsc-hub-bastion / t3.small
# ---------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "wsc-hub-bastion-sg"
  description = "Hub bastion - allow SSH inbound only"
  vpc_id      = aws_vpc.hub.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-hub-bastion-sg" }
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

resource "aws_iam_role" "bastion" {
  name               = "wsc-hub-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "wsc-hub-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = { Name = "wsc-hub-bastion-eip" }
}

locals {
  bastion_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf -y install jq tar gzip iputils bind-utils

    # awscli v2
    curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    cd /tmp && unzip -q awscliv2.zip && ./aws/install --update
    rm -rf /tmp/aws /tmp/awscliv2.zip

    # SSH Password 인증 활성화 + 패스워드 설정 (Skill53##)
    echo 'ec2-user:${var.ssh_password}' | chpasswd
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    mkdir -p /etc/ssh/sshd_config.d
    echo 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/60-wsc.conf
    systemctl restart sshd
  EOF
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.this["wsc-hub-sn-pub-a"].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data              = local.bastion_user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "wsc-hub-bastion" }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
