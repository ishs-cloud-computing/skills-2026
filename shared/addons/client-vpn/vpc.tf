# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC + private 서브넷. 원본: set-08 task-2 module-3 vpc.tf 범용화.
# IGW·NAT 없음 — 대상 EC2 는 VPN 으로만 접근하고 user-data 도 오프라인으로 끝난다.
# 기존 세트 VPC 에 부착하려면 이 파일을 지우고 aws_vpc.addon_vpn /
# aws_subnet.addon_vpn_private 참조를 기존 리소스로 바꾼다.
# ---------------------------------------------------------------------------

resource "aws_vpc" "addon_vpn" {
  cidr_block           = var.addon_vpn_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.addon_vpn_name}-vpc" }
}

resource "aws_subnet" "addon_vpn_private" {
  for_each = var.addon_vpn_private_subnets

  vpc_id            = aws_vpc.addon_vpn.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = each.key }
}
