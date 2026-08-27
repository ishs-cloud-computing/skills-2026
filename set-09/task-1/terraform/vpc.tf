# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# Public Subnet 전용 토폴로지 — 과제지 3장이 Private Subnet/NAT를 요구하지 않으며
# ECS Task는 Public Subnet + Public IP로 배치 (task.md 7.4). 채점 8-2가 불필요
# 리소스를 감점하므로 NAT/Endpoint는 생성하지 않는다.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.vpc_name
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.player_number}-public-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = local.igw_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = local.public_rt_name
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
