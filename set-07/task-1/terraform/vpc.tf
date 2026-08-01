# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC / Subnet / Routing (요구사항 3)
# - unicorn-vpc 10.97.0.0/16, 3 AZ(a,b,c)
# - public(0,1,2) : IGW 로 직접 인터넷, 공용 RTB unicorn-rt-pub
# - private(10,11,12) : AZ별 NAT(unicorn-nat-{a,b,c}) 경유, RTB unicorn-rt-priv-{a,b,c} 분리
# - App(private) 의 이미지/로그 트래픽은 endpoints.tf 의 VPC Endpoint(privateDNS)로 인터넷 미경유.
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "unicorn-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "unicorn-igw" }
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

# ----- Public Route Table : 공용 unicorn-rt-pub (IGW) -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "unicorn-rt-pub" }
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

# ----- AZ별 NAT Gateway : unicorn-nat-{a,b,c} (private 아웃바운드) -----
locals {
  # private 키 -> AZ suffix(a/b/c) 매핑 (NAT/RTB 이름에 사용)
  private_az_suffix = { for k, v in var.subnets : k => substr(v.az, -1, 1) if v.tier == "private" }
  # AZ -> public 키 매핑 (NAT 를 같은 AZ public 서브넷에 배치)
  public_by_az = { for k in local.public_subnet_keys : var.subnets[k].az => k }
}

resource "aws_eip" "nat" {
  for_each = toset(local.private_subnet_keys)
  domain   = "vpc"
  tags     = { Name = "unicorn-nat-eip-${local.private_az_suffix[each.key]}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.private_subnet_keys)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[local.public_by_az[var.subnets[each.key].az]].id
  tags          = { Name = "unicorn-nat-${local.private_az_suffix[each.key]}" }
  depends_on    = [aws_internet_gateway.this]
}

# ----- Private Route Tables : AZ별 unicorn-rt-priv-{a,b,c} (NAT) -----
resource "aws_route_table" "private" {
  for_each = toset(local.private_subnet_keys)
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "unicorn-rt-priv-${local.private_az_suffix[each.key]}" }
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
