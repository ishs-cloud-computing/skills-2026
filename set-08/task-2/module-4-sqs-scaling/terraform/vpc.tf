# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC (과제지 6-1: VPC 자유 구성)
# - public  : IGW 직접 인터넷 (NAT GW 배치)
# - private : NAT 경유 아웃바운드 (Addon NodeGroup / Karpenter 노드 배치)
# Karpenter 의 서브넷 자동 디스커버리를 위해 private 서브넷에
# karpenter.sh/discovery=<cluster_name> 태그를 부여한다 (k8s EC2NodeClass 참조).
# ---------------------------------------------------------------------------

locals {
  public_subnet_keys  = [for k, v in var.subnets : k if v.tier == "public"]
  private_subnet_keys = [for k, v in var.subnets : k if v.tier == "private"]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
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
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {},
    each.value.tier == "private" ? {
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      # Karpenter 서브넷 디스커버리 태그
      "karpenter.sh/discovery" = var.cluster_name
    } : {},
  )
}

# ----- Public Route Table : IGW -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-pub-rtb" }
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
  tags     = { Name = "${var.name_prefix}-nat-eip-${each.key}" }
}

locals {
  public_by_az = { for k in local.public_subnet_keys : var.subnets[k].az => k }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.private_subnet_keys)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[local.public_by_az[var.subnets[each.key].az]].id
  tags          = { Name = "${var.name_prefix}-nat-${each.key}" }
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
