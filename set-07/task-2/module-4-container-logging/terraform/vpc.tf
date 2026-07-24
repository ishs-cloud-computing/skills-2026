# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC (과제지 4. Container Logging)
# - public  : IGW 직접 인터넷 (ALB 2대, NAT GW 배치)
# - private : NAT 경유 아웃바운드 (EKS NodeGroup 배치, 2AZ = Multi-AZ 채점 4-1)
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "o11y-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "o11y-igw" }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = merge(
    { Name = each.key },
    each.value.tier == "public" ? {
      "kubernetes.io/role/elb" = "1"
    } : {},
    each.value.tier == "private" ? {
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {},
  )
}

# ----- Public Route Table : IGW -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "o11y-pub-rtb" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = toset(local.public_subnet_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ----- NAT Gateway (private 아웃바운드, AZ 별) -----
resource "aws_eip" "nat" {
  for_each = toset(local.private_subnet_keys)
  domain   = "vpc"
  tags     = { Name = "o11y-nat-eip-${each.key}" }
}

locals {
  public_by_az = { for k in local.public_subnet_keys : var.subnets[k].az => k }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.private_subnet_keys)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[local.public_by_az[var.subnets[each.key].az]].id
  tags          = { Name = "o11y-nat-${each.key}" }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  for_each = toset(local.private_subnet_keys)
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${each.key}-rtb" }
}

resource "aws_route" "private_nat" {
  for_each               = toset(local.private_subnet_keys)
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each       = toset(local.private_subnet_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
