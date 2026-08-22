# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPN 검증 대상 private EC2 — ICMP·SSH·HTTP 를 VPN 엔드포인트 SG 에서만 허용.
# 인터넷 경로가 없으므로 HTTP 는 패키지 설치 없이 python3 http.server 로 띄운다.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "addon_vpn_al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "addon_vpn_target" {
  name        = "${var.addon_vpn_ec2_name}-sg"
  description = "reachable from client vpn only"
  vpc_id      = aws_vpc.addon_vpn.id
  tags        = { Name = "${var.addon_vpn_ec2_name}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "addon_vpn_target" {
  for_each = {
    icmp = { protocol = "icmp", from = -1, to = -1 }
    ssh  = { protocol = "tcp", from = 22, to = 22 }
    http = { protocol = "tcp", from = 80, to = 80 }
  }

  security_group_id            = aws_security_group.addon_vpn_target.id
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.addon_vpn.id
  description                  = "${each.key} from client vpn"
}

resource "aws_vpc_security_group_egress_rule" "addon_vpn_target_all" {
  security_group_id = aws_security_group.addon_vpn_target.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "all outbound"
}

resource "aws_instance" "addon_vpn_target" {
  ami                    = data.aws_ssm_parameter.addon_vpn_al2023.value
  instance_type          = var.addon_vpn_ec2_instance_type
  subnet_id              = values(aws_subnet.addon_vpn_private)[0].id
  vpc_security_group_ids = [aws_security_group.addon_vpn_target.id]
  key_name               = var.addon_vpn_ec2_key_name != "" ? var.addon_vpn_ec2_key_name : null

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /var/www
    echo "hello from $(hostname -f) via client vpn" > /var/www/index.html
    cat > /etc/systemd/system/hello-http.service <<'UNIT'
    [Unit]
    Description=hello http
    After=network.target
    [Service]
    WorkingDirectory=/var/www
    ExecStart=/usr/bin/python3 -m http.server 80
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now hello-http
  EOT

  tags = { Name = var.addon_vpn_ec2_name }
}
