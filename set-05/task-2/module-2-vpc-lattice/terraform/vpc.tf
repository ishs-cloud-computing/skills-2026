# ---------------------------------------------------------------------------
# Hub / Spoke VPC (과제지 4. VPC Lattice - VPC 구성)
# - Hub   : 10.0.0.0/16, public(IGW) — Bastion 배치
# - Spoke : 192.168.0.0/16, public(IGW) + private(NAT) — App 서버 배치
# 두 VPC 는 직접 Peering 하지 않으며, 통신은 VPC Lattice 로만 수행한다 (lattice.tf).
# ---------------------------------------------------------------------------

resource "aws_vpc" "hub" {
  cidr_block           = var.hub_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "wsc-hub-vpc" }
}

resource "aws_vpc" "spoke" {
  cidr_block           = var.spoke_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "wsc-spoke-vpc" }
}

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id
  tags   = { Name = "wsc-hub-igw" }
}

resource "aws_internet_gateway" "spoke" {
  vpc_id = aws_vpc.spoke.id
  tags   = { Name = "wsc-spoke-igw" }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = local.vpc_ids[each.value.vpc]
  cidr_block              = each.value.cidr
  availability_zone       = "${var.region}${each.value.az}"
  map_public_ip_on_launch = each.value.tier == "public"

  tags = { Name = each.key }
}

# ----- Hub Public Route Table -----
resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub.id
  tags   = { Name = "wsc-hub-pub-rtb" }
}

resource "aws_route" "hub_public_igw" {
  route_table_id         = aws_route_table.hub_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.hub.id
}

resource "aws_route_table_association" "hub_public" {
  for_each       = toset(local.hub_public_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.hub_public.id
}

# ----- Spoke Public Route Table -----
resource "aws_route_table" "spoke_public" {
  vpc_id = aws_vpc.spoke.id
  tags   = { Name = "wsc-spoke-pub-rtb" }
}

resource "aws_route" "spoke_public_igw" {
  route_table_id         = aws_route_table.spoke_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.spoke.id
}

resource "aws_route_table_association" "spoke_public" {
  for_each       = toset(local.spoke_public_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.spoke_public.id
}

# ----- Spoke Private : NAT (AZ 별) -----
resource "aws_eip" "nat" {
  for_each = toset(local.spoke_private_keys)
  domain   = "vpc"
  tags     = { Name = "wsc-spoke-nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.spoke_private_keys)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[local.spoke_public_by_az[var.subnets[each.key].az]].id
  tags          = { Name = "wsc-spoke-nat-${each.key}" }
  depends_on    = [aws_internet_gateway.spoke]
}

resource "aws_route_table" "spoke_private" {
  for_each = toset(local.spoke_private_keys)
  vpc_id   = aws_vpc.spoke.id
  tags     = { Name = "${each.key}-rtb" }
}

resource "aws_route" "spoke_private_nat" {
  for_each               = toset(local.spoke_private_keys)
  route_table_id         = aws_route_table.spoke_private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "spoke_private" {
  for_each       = toset(local.spoke_private_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.spoke_private[each.key].id
}
