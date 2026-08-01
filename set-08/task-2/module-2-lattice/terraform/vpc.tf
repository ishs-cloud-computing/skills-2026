# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC 2개 (과제지 4-1). Client ↔ Service 간 peering/TGW 금지 —
# 연결은 VPC Lattice 데이터 플레인만 사용한다 (lattice.tf).
# 두 EC2 모두 Public IP 필요 (채점 2-2가 PublicIp 필드 확인) → public 서브넷.
# ---------------------------------------------------------------------------

resource "aws_vpc" "client" {
  cidr_block           = var.client_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.client_vpc_name }
}

resource "aws_vpc" "service" {
  cidr_block           = var.service_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.service_vpc_name }
}

resource "aws_internet_gateway" "client" {
  vpc_id = aws_vpc.client.id
  tags   = { Name = "${var.client_vpc_name}-igw" }
}

resource "aws_internet_gateway" "service" {
  vpc_id = aws_vpc.service.id
  tags   = { Name = "${var.service_vpc_name}-igw" }
}

resource "aws_subnet" "client" {
  vpc_id                  = aws_vpc.client.id
  cidr_block              = var.client_subnet_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.client_vpc_name}-sn" }
}

resource "aws_subnet" "service" {
  vpc_id                  = aws_vpc.service.id
  cidr_block              = var.service_subnet_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.service_vpc_name}-sn" }
}

resource "aws_route_table" "client" {
  vpc_id = aws_vpc.client.id
  tags   = { Name = "${var.client_vpc_name}-rtb" }
}

resource "aws_route" "client_igw" {
  route_table_id         = aws_route_table.client.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.client.id
}

resource "aws_route_table_association" "client" {
  subnet_id      = aws_subnet.client.id
  route_table_id = aws_route_table.client.id
}

resource "aws_route_table" "service" {
  vpc_id = aws_vpc.service.id
  tags   = { Name = "${var.service_vpc_name}-rtb" }
}

resource "aws_route" "service_igw" {
  route_table_id         = aws_route_table.service.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.service.id
}

resource "aws_route_table_association" "service" {
  subnet_id      = aws_subnet.service.id
  route_table_id = aws_route_table.service.id
}
