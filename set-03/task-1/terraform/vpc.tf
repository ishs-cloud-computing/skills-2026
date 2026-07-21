# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC / Subnet / Routing (요구사항 3, Reference01)
# - wsc2026-skills-vpc 192.168.0.0/16, 2 AZ(a,b)
# - hub(public)  : 공용 RTB wsc2026-skills-hub-rtb → wsc2026-skills-igw
# - app(private) : AZ별 RTB wsc2026-skills-app-rtb-{a,b} → wsc2026-skills-nat-{a,b}
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-skills-igw" }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = merge(
    { Name = each.key },
    # AWS Load Balancer Controller 의 서브넷 자동 디스커버리용 태그
    each.value.tier == "public" ? {
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      } : {
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    },
  )
}

# ----- Public Route Table : 공용 wsc2026-skills-hub-rtb (IGW) -----
resource "aws_route_table" "hub" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-skills-hub-rtb" }
}

resource "aws_route" "hub_igw" {
  route_table_id         = aws_route_table.hub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "hub" {
  for_each       = toset(local.public_subnet_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.hub.id
}

# ----- AZ별 NAT Gateway : wsc2026-skills-nat-{a,b} (hub 서브넷에 배치) -----
locals {
  # private 키 → AZ suffix(a/b) 매핑 (NAT/RTB 이름에 사용)
  private_az_suffix = { for k, v in var.subnets : k => substr(v.az, -1, 1) if v.tier == "private" }
  # AZ → public 키 매핑 (NAT 를 같은 AZ hub 서브넷에 배치)
  public_by_az = { for k in local.public_subnet_keys : var.subnets[k].az => k }
}

resource "aws_eip" "nat" {
  for_each = toset(local.private_subnet_keys)
  domain   = "vpc"
  tags     = { Name = "${var.name_prefix}-skills-nat-eip-${local.private_az_suffix[each.key]}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.private_subnet_keys)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[local.public_by_az[var.subnets[each.key].az]].id
  tags          = { Name = "${var.name_prefix}-skills-nat-${local.private_az_suffix[each.key]}" }
  depends_on    = [aws_internet_gateway.this]
}

# ----- Private Route Tables : AZ별 wsc2026-skills-app-rtb-{a,b} (NAT) -----
resource "aws_route_table" "app" {
  for_each = toset(local.private_subnet_keys)
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name_prefix}-skills-app-rtb-${local.private_az_suffix[each.key]}" }
}

resource "aws_route" "app_nat" {
  for_each               = toset(local.private_subnet_keys)
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "app" {
  for_each       = toset(local.private_subnet_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}