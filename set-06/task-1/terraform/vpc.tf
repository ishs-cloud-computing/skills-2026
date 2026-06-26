# ---------------------------------------------------------------------------
# VPC (요구사항 3, Reference01)
# - gj2026-vpc 10.0.0.0/16
# - 인터넷 통신이 불가능한 Private subnet 2개만 존재 (public/NAT 없음)
# - CloudFront VPC Origin 연동을 위해 IGW 를 VPC 에 "연결만" 한다.
#   (어떤 라우트 테이블에도 IGW 라우트를 추가하지 않으므로 인터넷 통신 불가)
# - 노드/ALB/Lambda/Endpoint 모두 이 2개 private subnet 에 배치
# - AWS 서비스 통신은 Interface VPC Endpoint(ENI) 로만 수행 (endpoints.tf)
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "gj2026-vpc" }
}

# 채점 1-3: IGW 는 VPC 에 attach 되어 있어야 하나, 라우트는 없어야 한다.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "gj2026-igw" }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = each.key
    # ALB Controller / eksctl 서브넷 디스커버리 + 내부 ELB 배치용 태그
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ----- Private Route Tables (Reference01: gj2026-private-rtb-a / -b) -----
# 채점 1-2: 라우트는 local(10.0.0.0/16) 만 존재해야 한다.
# aws_route 를 의도적으로 생성하지 않는다 (local 라우트는 암묵적으로 존재).
resource "aws_route_table" "private" {
  for_each = var.subnets
  vpc_id   = aws_vpc.this.id
  tags     = { Name = replace(each.key, "subnet", "rtb") }
}

resource "aws_route_table_association" "private" {
  for_each       = var.subnets
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
