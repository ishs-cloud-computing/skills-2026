#!/bin/bash
set -euxo pipefail

# SSH Password 인증 활성화 + 패스워드 설정 (curl 실패와 무관하게 보장)
echo 'ec2-user:${ssh_password}' | chpasswd
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
echo 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/60-wsc.conf
systemctl restart sshd

dnf -y update
dnf -y install jq tar gzip iputils bind-utils git tmux

# docker
dnf -y install docker
systemctl enable --now docker
usermod -aG docker ec2-user

# terraform
yum install -y yum-utils shadow-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum install -y terraform

# kubectl (EKS 1.35 대응)
curl -sLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# eksctl
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin/

# helm (Prometheus/Grafana/LB Controller 설치용)
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# .bashrc 자동완성 (ec2-user)
cat >> /home/ec2-user/.bashrc << 'BASHRC'

# --- kubectl ---
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k

# --- eksctl ---
source <(eksctl completion bash)

# --- helm ---
source <(helm completion bash)

# --- aws cli ---
complete -C '/usr/local/bin/aws_completer' aws
BASHRC
chown ec2-user:ec2-user /home/ec2-user/.bashrc
