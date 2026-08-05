# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC 1개 (과제지 3-1). Client EC2 는 Public IP 로 외부 접근 → public 서브넷.
# DocumentDB 는 외부 직접 노출 금지 → 전용 서브넷 2개(IGW 라우트 없음).
# subnet group 이 서로 다른 AZ 2개를 요구해 db 서브넷은 항상 2개 유지.
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.vpc_name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_az
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.vpc_name}-sn-pub" }
}

resource "aws_subnet" "db" {
  for_each = var.db_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = each.key }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.vpc_name}-rtb-pub" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_docdb_subnet_group" "this" {
  name       = "${var.docdb_cluster_identifier}-subnets"
  subnet_ids = [for s in aws_subnet.db : s.id]
}
