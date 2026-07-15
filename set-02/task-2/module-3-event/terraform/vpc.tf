# ---------------------------------------------------------------------------
# VPC (과제지 1. VPC — 퍼블릭 2AZ, NAT 없음)
# - 서브넷/RTB/IGW Name 태그는 과제지 표와 정확 일치
# ---------------------------------------------------------------------------

resource "aws_vpc" "event" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "event" {
  vpc_id = aws_vpc.event.id

  tags = { Name = var.igw_name }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.event.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = { Name = each.key }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.event.id

  tags = { Name = var.pub_rtb_name }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.event.id
}

resource "aws_route_table_association" "public" {
  for_each = { for name, s in var.subnets : name => s if s.tier == "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}
