# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC (과제지 1. VPC — 퍼블릭/프라이빗 2AZ, 단일 NAT)
# - 서브넷/RTB/IGW/NAT Name 태그는 과제지 표와 정확 일치
# ---------------------------------------------------------------------------

resource "aws_vpc" "msk" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "msk" {
  vpc_id = aws_vpc.msk.id

  tags = { Name = var.igw_name }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.msk.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = { Name = each.key }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.nat_name}-eip" }
}

resource "aws_nat_gateway" "msk" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this[var.nat_subnet_name].id

  tags = { Name = var.nat_name }

  depends_on = [aws_internet_gateway.msk]
}

# ----- 퍼블릭 라우팅 (공용 RTB) -----

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.msk.id

  tags = { Name = var.pub_rtb_name }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.msk.id
}

resource "aws_route_table_association" "public" {
  for_each = { for name, s in var.subnets : name => s if s.tier == "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ----- 프라이빗 라우팅 (서브넷별 RTB, 단일 NAT 공유) -----

resource "aws_route_table" "private" {
  for_each = var.priv_rtb_names

  vpc_id = aws_vpc.msk.id

  tags = { Name = each.value }
}

resource "aws_route" "private_default" {
  for_each = var.priv_rtb_names

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.msk.id
}

resource "aws_route_table_association" "private" {
  for_each = var.priv_rtb_names

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
