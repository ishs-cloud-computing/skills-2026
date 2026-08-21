# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC — 퍼블릭 2 AZ 만 (ALB 2 AZ 요건). 원본: set-02 task-2 module-2 vpc.tf.
# EC2 를 퍼블릭에 두고 NAT 를 생략한다 — 이미지 pull·SSM 은 퍼블릭 IP 로 나간다.
# 과제지가 프라이빗 배치를 요구하면 set-02 vpc.tf 의 NAT·priv RTB 블록을 가져온다.
# ---------------------------------------------------------------------------

resource "aws_vpc" "addon_kc" {
  cidr_block           = var.addon_kc_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.addon_kc_vpc_name }
}

resource "aws_internet_gateway" "addon_kc" {
  vpc_id = aws_vpc.addon_kc.id

  tags = { Name = "${var.addon_kc_vpc_name}-igw" }
}

resource "aws_subnet" "addon_kc_public" {
  for_each = var.addon_kc_public_subnets

  vpc_id                  = aws_vpc.addon_kc.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = { Name = each.key }
}

resource "aws_route_table" "addon_kc_public" {
  vpc_id = aws_vpc.addon_kc.id

  tags = { Name = "${var.addon_kc_vpc_name}-pub-rtb" }
}

resource "aws_route" "addon_kc_public_default" {
  route_table_id         = aws_route_table.addon_kc_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.addon_kc.id
}

resource "aws_route_table_association" "addon_kc_public" {
  for_each = var.addon_kc_public_subnets

  subnet_id      = aws_subnet.addon_kc_public[each.key].id
  route_table_id = aws_route_table.addon_kc_public.id
}
