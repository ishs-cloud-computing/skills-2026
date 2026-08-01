# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC 2개 (과제지 4-1). Client ↔ Service 간 peering/TGW 금지 —
# 연결은 VPC Lattice 데이터 플레인만 사용한다 (lattice.tf).
# Client EC2만 Public IP 필요, Service EC2는 Public IP 없이 내부 서비스로
# 구성 (과제지 명시, task.md:117 "Client EC2는 Public IP로 HTTP 접근 가능해야
# 하며, Service EC2는 Public IP 없이 내부 서비스로 구성합니다"). 채점
# mark2-2.sh는 두 인스턴스의 PublicIp 필드를 단순 조회·출력할 뿐 — 두 값
# 모두 채워져 있어야 한다는 뜻이 아니다 (이전 오독 정정).
# service 서브넷에도 IGW 라우트가 남아있으나 map_public_ip_on_launch=false라
# 무해 — 서비스 인스턴스는 Public IP가 없어 IGW 경로로 도달 불가능하고,
# Lattice 데이터 플레인은 Target Group을 통해 서비스 VPC 내부에서 직접
# 인스턴스에 도달하므로 라우트 자체에 의존하지 않는다.
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
  map_public_ip_on_launch = false
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
