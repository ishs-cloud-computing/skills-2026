# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_vpc" "this" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name = "skills-vpc"
  }
}

resource "aws_subnet" "public" {
  count = length(local.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
    # AWS Load Balancer Controller가 internet-facing ALB를 놓을 서브넷을
    # 이 태그로 자동 발견한다 (Ingress에 subnets를 나열하지 않아도 되는 이유).
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count = length(local.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "private-subnet-${count.index + 1}"
    # EC2NodeClass subnetSelectorTerms가 이 태그로 노드 서브넷을 선택한다.
    # 값은 eksctl cluster.yaml의 metadata.tags와 동일해야 한다.
    "karpenter.sh/discovery" = local.cluster_name
    # internal ELB용 서브넷 표시 (LBC가 internal 스킴을 쓸 때 대비)
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "skills-igw"
  }
}

resource "aws_nat_gateway" "this" {
  vpc_id            = aws_vpc.this.id
  availability_mode = "regional"

  tags = {
    Name = "skills-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "s3-vpce"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "public-rtb"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "private-rtb"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
