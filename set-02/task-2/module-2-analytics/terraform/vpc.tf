# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC (과제지 1. VPC — 고가용성 2AZ)
# - 서브넷 Name 태그는 mark 2-1 이 그대로 출력하므로 과제지 표와 정확 일치
# - NAT 는 과제지 표대로 analytics-ngw 1개 (두 프라이빗 RTB 가 공유)
# ---------------------------------------------------------------------------

resource "aws_vpc" "analytics" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "analytics" {
  vpc_id = aws_vpc.analytics.id

  tags = { Name = var.igw_name }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.analytics.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = { Name = each.key }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.nat_name}-eip" }
}

resource "aws_nat_gateway" "analytics" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this[var.nat_subnet_name].id

  tags = { Name = var.nat_name }

  depends_on = [aws_internet_gateway.analytics]
}

# ----- 퍼블릭 라우팅 (공용 RTB) -----

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.analytics.id

  tags = { Name = var.pub_rtb_name }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.analytics.id
}

resource "aws_route_table_association" "public" {
  for_each = { for name, s in var.subnets : name => s if s.tier == "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ----- 프라이빗 라우팅 (서브넷별 RTB, 단일 NAT 공유) -----

resource "aws_route_table" "private" {
  for_each = var.priv_rtb_names

  vpc_id = aws_vpc.analytics.id

  tags = { Name = each.value }
}

resource "aws_route" "private_default" {
  for_each = var.priv_rtb_names

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.analytics.id
}

resource "aws_route_table_association" "private" {
  for_each = var.priv_rtb_names

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
