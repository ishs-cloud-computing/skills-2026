# ---------------------------------------------------------------------------
# Bastion (유의사항: 채점 커맨드는 Bastion/CloudShell 에서 수행)
# - analytics-pub-a 배치, EIP 로 재시작 시에도 IP 고정
# - SSH Password 방식, mark2-1.sh/mark2-2.sh 실행용 Admin 권한 + jq/awscli
# ---------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "wsc2026-analytics-bastion-sg"
  description = "Bastion - allow SSH inbound only"
  vpc_id      = aws_vpc.analytics.id

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

  tags = { Name = "wsc2026-analytics-bastion-sg" }
}

resource "aws_iam_role" "bastion" {
  name               = "wsc2026-analytics-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "wsc2026-analytics-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = { Name = "wsc2026-analytics-bastion-eip" }
}

locals {
  bastion_user_data = <<-EOF
    #!/bin/bash
    # set -e 는 일부러 뺀다: 뒤쪽 툴 설치가 하나 실패해도 cloud-final 이 죽으면
    # SSH 설정이 안 돼서 패스워드 로그인 자체가 불가해진다. 끝까지 실행되어야 한다.
    set -uxo pipefail

    # ===== 1) SSH 패스워드 인증 (최우선: 네트워크 불필요, 항상 성공) =====
    set +x   # 패스워드가 cloud-init-output 로그에 평문으로 찍히지 않게 xtrace off
    echo 'ec2-user:${var.ssh_password}' | chpasswd
    set -x
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    mkdir -p /etc/ssh/sshd_config.d
    # cloud-init drop-in(50-cloud-init.conf)보다 먼저 매칭되도록 00- 사용 (sshd 는 옵션별 first-match 우선)
    printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/00-wsc-pwauth.conf
    systemctl restart sshd

    # ===== 2) 툴 설치 (mark 스크립트용 jq/curl/awscli, 실패해도 cloud-final 을 죽이지 않음) =====
    dnf -y install jq tar gzip iputils bind-utils || true

    # awscli v2
    if curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip; then
      (cd /tmp && unzip -q awscliv2.zip && ./aws/install --update)
      rm -rf /tmp/aws /tmp/awscliv2.zip
    fi
  EOF
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.this[var.nat_subnet_name].id
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

  tags = { Name = "wsc2026-analytics-bastion" }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
