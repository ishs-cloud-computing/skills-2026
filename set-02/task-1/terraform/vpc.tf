# ---------------------------------------------------------------------------
# VPC / Subnet / Routing (요구사항 3 / Reference01)
# - wskorea26-vpc 172.16.0.0/16, AZ c/d
# - public(1,2)     : book-igw 직접 인터넷, 공용 RTB wskorea26-public-rtb
# - private(201,202): AZ별 NAT(book-ngw-{c,d}) 경유, RTB wskorea26-private-rtb-{c,d} 분리
# mark 1-1(CIDR), 1-2(RTB 연결/기본 라우트 GatewayId·NatGatewayId)가 이 구성을 그대로 검사한다.
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.igw_name }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = { Name = each.key }
}

# ----- Public Route Table : 공용 wskorea26-public-rtb (book-igw) -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.public_rtb_name }
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

# ----- AZ별 NAT Gateway : book-ngw-{c,d} (private 아웃바운드) -----
locals {
  # private 키 -> AZ suffix(c/d) 매핑 (NAT/RTB 이름에 사용)
  private_az_suffix = { for k, v in var.subnets : k => substr(v.az, -1, 1) if v.tier == "private" }
  # AZ -> public 키 매핑 (NAT 를 같은 AZ public 서브넷에 배치)
  public_by_az = { for k in local.public_subnet_keys : var.subnets[k].az => k }
}

resource "aws_eip" "nat" {
  for_each = toset(local.private_subnet_keys)
  domain   = "vpc"
  tags     = { Name = "${var.nat_name_prefix}-eip-${local.private_az_suffix[each.key]}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.private_subnet_keys)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[local.public_by_az[var.subnets[each.key].az]].id
  tags          = { Name = "${var.nat_name_prefix}-${local.private_az_suffix[each.key]}" }
  depends_on    = [aws_internet_gateway.this]
}

# ----- Private Route Tables : AZ별 wskorea26-private-rtb-{c,d} (NAT) -----
resource "aws_route_table" "private" {
  for_each = toset(local.private_subnet_keys)
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.private_rtb_name_prefix}-${local.private_az_suffix[each.key]}" }
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
