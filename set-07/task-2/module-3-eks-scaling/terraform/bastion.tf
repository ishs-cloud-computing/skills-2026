# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Bastion (작업 호스트)
# - Public Subnet AZ A 배치, EIP 로 재시작 시에도 IP 고정
# - 대회 PC 에 Docker/WSL 이 없으므로 이미지 빌드도 여기서 한다 (docker 설치)
# - kubectl / eksctl / helm 사전 설치 (eksctl 클러스터 생성 / KEDA·Karpenter 배포)
# - 클러스터 생성 전 `aws configure` 로 선수 IAM 키를 넣어 생성자 신원을
#   채점 CloudShell 신원과 일치시킨다 (README 참조) — 인스턴스 프로파일은 보조.
# ---------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "skm-bastion-sg"
  description = "Bastion - allow SSH inbound only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
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

  tags = { Name = "skm-bastion-sg" }
}

resource "aws_iam_role" "bastion" {
  name               = "skm-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "skm-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = { Name = "skm-bastion-eip" }
}

locals {
  bastion_user_data = <<EOF
#!/bin/bash
# set -e 는 일부러 빼둔다: 뒤쪽 툴 다운로드가 하나 실패해도 cloud-final 이 죽으면
# 안 되고(=SSH 설정이 안 돼서 로그인 불가), 전체가 끝까지 실행되어야 한다.
set -uxo pipefail

# ===== 1) SSH 비밀번호 인증 (맨 앞: 네트워크 불필요, 항상 성공) =====
set +x   # 비밀번호가 콘솔 로그에 평문으로 찍히지 않게 xtrace off
echo 'ec2-user:${var.ssh_password}' | chpasswd
set -x
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
# cloud-init drop-in(50-cloud-init.conf)보다 먼저 매칭되도록 00- 사용 (sshd 는 옵션별 first-match 우선)
printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/00-skm-pwauth.conf
systemctl restart sshd

# ===== 2) 툴 설치 (실패해도 || true 로 cloud-final 을 죽이지 않음) =====
dnf -y update || true
dnf -y install jq unzip tar gzip iputils bind-utils git tmux gettext || true

# docker (이미지 빌드 호스트 — 대회 PC 에 Docker 없음)
dnf -y install docker || true
systemctl enable --now docker || true
usermod -aG docker ec2-user || true

# awscli v2
if curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip; then
  (cd /tmp && unzip -q awscliv2.zip && ./aws/install --update)
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

# kubectl (EKS 1.35 대응)
curl -sLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.35.6/bin/linux/amd64/kubectl" && chmod +x /usr/local/bin/kubectl

# eksctl
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp && mv -f /tmp/eksctl /usr/local/bin/ || true

# helm (KEDA / Karpenter 설치용)
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || true

cat >> /home/ec2-user/.bashrc << 'BASHRC'
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
source <(eksctl completion bash)
source <(helm completion bash)
complete -C '/usr/local/bin/aws_completer' aws
BASHRC
chown ec2-user:ec2-user /home/ec2-user/.bashrc

exit 0
EOF
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.this["skm-subnet-pub-a"].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data              = local.bastion_user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 강제
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "skm-bastion" }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
