# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Client VPN 엔드포인트 — mutual TLS (인증서는 README 절차로 생성·ACM import)
# + 서브넷 연결 + 인가 규칙(VPC 전체) + CloudWatch 접속 로그.
# 저장소에 실전 구현 없음 — provider 6.x 문서 기준.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "addon_vpn" {
  name              = "/aws/clientvpn/${var.addon_vpn_name}"
  retention_in_days = var.addon_vpn_log_retention_days
}

resource "aws_cloudwatch_log_stream" "addon_vpn" {
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.addon_vpn.name
}

# 엔드포인트 ENI 에 붙는 SG. VPN 클라이언트 트래픽은 이 ENI IP 로 SNAT 되어 VPC 에 들어가므로
# 대상 EC2 SG 는 클라이언트 CIDR 이 아니라 이 SG 를 소스로 허용한다.
resource "aws_security_group" "addon_vpn" {
  name        = "${var.addon_vpn_name}-sg"
  description = "client vpn endpoint"
  vpc_id      = aws_vpc.addon_vpn.id
  tags        = { Name = "${var.addon_vpn_name}-sg" }
}

resource "aws_vpc_security_group_egress_rule" "addon_vpn_all" {
  security_group_id = aws_security_group.addon_vpn.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "vpn clients to vpc"
}

resource "aws_ec2_client_vpn_endpoint" "addon" {
  description            = var.addon_vpn_name
  server_certificate_arn = var.addon_vpn_server_cert_arn
  client_cidr_block      = var.addon_vpn_client_cidr
  split_tunnel           = var.addon_vpn_split_tunnel
  transport_protocol     = var.addon_vpn_transport_protocol
  vpn_port               = 443
  vpc_id                 = aws_vpc.addon_vpn.id
  security_group_ids     = [aws_security_group.addon_vpn.id]

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = coalesce(var.addon_vpn_client_root_cert_arn, var.addon_vpn_server_cert_arn)
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.addon_vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.addon_vpn.name
  }

  tags = { Name = var.addon_vpn_name }
}

# 서브넷 연결 — 서브넷당 ENI 1개·시간당 과금. 연결 완료까지 수 분.
resource "aws_ec2_client_vpn_network_association" "addon" {
  for_each = aws_subnet.addon_vpn_private

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.addon.id
  subnet_id              = each.value.id
}

# 연결만으로는 트래픽이 안 흐른다 — 대상 CIDR 인가 규칙이 있어야 한다 (VPC 전체).
resource "aws_ec2_client_vpn_authorization_rule" "addon_vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.addon.id
  target_network_cidr    = aws_vpc.addon_vpn.cidr_block
  authorize_all_groups   = true
  description            = "vpc"
}
