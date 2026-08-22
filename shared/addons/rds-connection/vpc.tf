# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC — public 1 (NAT) + private 2AZ (RDS·Proxy·클라이언트 EC2)
# 원본: set-02 task-2 module-2 vpc.tf, set-08 task-2 module-1 vpc.tf 범용화.
# 클라이언트 EC2 가 private 에서 SSM·dnf 를 쓰므로 NAT 1개가 필요하다.
# 기존 세트 VPC 에 부착하려면 이 파일을 지우고 다른 파일의 aws_vpc.addon_rds /
# aws_subnet.addon_rds_private 참조를 기존 리소스로 바꾼다.
# ---------------------------------------------------------------------------

resource "aws_vpc" "addon_rds" {
  cidr_block           = var.addon_rds_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.addon_rds_name_prefix}-vpc" }
}

resource "aws_internet_gateway" "addon_rds" {
  vpc_id = aws_vpc.addon_rds.id
  tags   = { Name = "${var.addon_rds_name_prefix}-igw" }
}

resource "aws_subnet" "addon_rds_public" {
  vpc_id                  = aws_vpc.addon_rds.id
  cidr_block              = var.addon_rds_public_subnet.cidr
  availability_zone       = var.addon_rds_public_subnet.az
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.addon_rds_name_prefix}-public" }
}

resource "aws_subnet" "addon_rds_private" {
  for_each = var.addon_rds_private_subnets

  vpc_id            = aws_vpc.addon_rds.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = each.key }
}

resource "aws_eip" "addon_rds_nat" {
  domain = "vpc"
  tags   = { Name = "${var.addon_rds_name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "addon_rds" {
  allocation_id = aws_eip.addon_rds_nat.id
  subnet_id     = aws_subnet.addon_rds_public.id
  tags          = { Name = "${var.addon_rds_name_prefix}-nat" }

  depends_on = [aws_internet_gateway.addon_rds]
}

resource "aws_route_table" "addon_rds_public" {
  vpc_id = aws_vpc.addon_rds.id
  tags   = { Name = "${var.addon_rds_name_prefix}-public-rtb" }
}

resource "aws_route" "addon_rds_public_default" {
  route_table_id         = aws_route_table.addon_rds_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.addon_rds.id
}

resource "aws_route_table_association" "addon_rds_public" {
  subnet_id      = aws_subnet.addon_rds_public.id
  route_table_id = aws_route_table.addon_rds_public.id
}

resource "aws_route_table" "addon_rds_private" {
  vpc_id = aws_vpc.addon_rds.id
  tags   = { Name = "${var.addon_rds_name_prefix}-private-rtb" }
}

resource "aws_route" "addon_rds_private_default" {
  route_table_id         = aws_route_table.addon_rds_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.addon_rds.id
}

resource "aws_route_table_association" "addon_rds_private" {
  for_each = aws_subnet.addon_rds_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.addon_rds_private.id
}
