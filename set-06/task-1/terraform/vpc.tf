# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC / Subnet / RTB / IGW / Endpoint / SG (NOTES.md §3.1)
# - NAT 없음(채점 1-3), Private 서브넷 정확히 2개(1-1), 라우트 추가 금지(1-2)
# - Gateway Endpoint 라우트는 DestinationCidrBlock 키가 없어 1-2 쿼리에서 자동 제외
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # Interface Endpoint private DNS 에 필수

  tags = { Name = "${var.name_prefix}-vpc" }
}

# 채점 1-1 이 VPC 내 전 서브넷을 나열 비교 — 3번째 서브넷을 만들면 즉시 오답
resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # EKS 가 내부 ELB 서브넷을 자동 발견하도록 태깅
  tags = {
    Name                              = "${var.name_prefix}-private-subnet-${substr(var.azs[count.index], -1, 1)}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# 라우트를 하나도 추가하지 않는다 — local 만 존재해야 1-2 통과
resource "aws_route_table" "private" {
  count = length(var.azs)

  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-private-rtb-${substr(var.azs[count.index], -1, 1)}" }
}

resource "aws_route_table_association" "private" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# CloudFront VPC Origin 전제 조건 — attach 만 하고 어떤 RTB 에도 연결하지 않는다
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# ---------------------------------------------------------------------------
# Gateway Endpoint — DynamoDB 는 Gateway 전용(Interface 미존재), S3 는 ECR 레이어 경로
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(["s3", "dynamodb"])

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${var.name_prefix}-${each.value}-gw-ep" }
}

# ---------------------------------------------------------------------------
# Interface Endpoint — NAT 없는 환경에서 AWS API 유일 경로
# ---------------------------------------------------------------------------

locals {
  interface_endpoints = [
    "ecr.api", "ecr.dkr",          # 이미지 pull
    "logs",                        # Fluent Bit / Lambda 로그
    "monitoring",                  # Grafana CloudWatch 데이터소스
    "sts",                         # IRSA 토큰 교환
    "ec2", "elasticloadbalancing", # LBC / CCM
    "kms", "eks", "autoscaling",
    "ssm", "ssmmessages", "ec2messages", # SSM 세션 매니저 (디버깅/노드 접근 유일 경로)
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-${replace(each.value, ".", "-")}-ep" }
}

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------

resource "aws_security_group" "endpoint" {
  name        = "${var.name_prefix}-endpoint-sg"
  description = "Interface endpoint - allow 443 from VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-endpoint-sg" }
}

# CloudFront VPC Origin 트래픽은 ENI 를 통해 들어오지만 소스 IP 가 CloudFront POP
# 공인 대역(54.182.x 등)으로 찍힌다 — VPC CIDR 허용만으로는 REJECT (Flow Log 실측, NOTES.md §6 함정 34).
# 공식 문서 옵션 1: origin-facing managed prefix list 허용 (서비스 SG 는 vpc origin 생성 후에야 존재해 순서 문제).
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "internal ALB - allow 80 from CloudFront VPC Origin ENI" # ForceNew 필드 — 바꾸면 SG 재생성 시도 (ALB 부착 중이라 실패)
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from CloudFront VPC Origin (POP source IP)"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  ingress {
    description = "HTTP from VPC (in-cluster verification)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

# 노드그룹에 추가 attach 하는 공용 SG — Grafana(3000, SGP 미적용 addon 노드) 수신용
resource "aws_security_group" "node_shared" {
  name        = "${var.name_prefix}-node-sg"
  description = "extra node SG - grafana target port from ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Grafana target port from ALB"
    from_port       = var.grafana_port
    to_port         = var.grafana_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # CoreDNS 는 노드 ENI(이 SG) 뒤에 있다 — SGP 파드(branch ENI)는 book_pod SG 만 달고 있어
  # 별도 허용 없이는 DNS 53 이 막힌다 (실측: DNS 행 → STS/DDB 전부 불통 → 8-2 504).
  # 주의: 이 SG 는 인라인 ingress 방식 — 별도 aws_security_group_rule 로 추가하면
  # 다음 full apply 때 인라인 정확집합 강제로 삭제된다 (실측 재발). 반드시 인라인 유지.
  ingress {
    description     = "CoreDNS UDP from book pod SG"
    from_port       = 53
    to_port         = 53
    protocol        = "udp"
    security_groups = [aws_security_group.book_pod.id]
  }

  ingress {
    description     = "CoreDNS TCP from book pod SG"
    from_port       = 53
    to_port         = 53
    protocol        = "tcp"
    security_groups = [aws_security_group.book_pod.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-node-sg" }
}

# ---------------------------------------------------------------------------
# book Pod SG (채점 4-5, NOTES.md §3.6.1) — SecurityGroupPolicy 로 branch ENI 에 부착
# - ingress 는 ALB SG 참조뿐 → nginx-test(노드 primary ENI 소스)는 자동 차단
# - Gateway Endpoint 는 ENI 가 없어 SG 참조 불가 → prefix list 로 egress 개방
# ---------------------------------------------------------------------------

data "aws_prefix_list" "dynamodb" {
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.${var.region}.dynamodb"]
  }
}

resource "aws_security_group" "book_pod" {
  name        = "${var.name_prefix}-book-pod-sg"
  description = "book pod branch ENI - ingress from ALB only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "app port from ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description     = "AWS API via interface endpoints (STS, Logs, ...)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.endpoint.id]
  }

  egress {
    description     = "DynamoDB via gateway endpoint (prefix list)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_prefix_list.dynamodb.id]
  }

  # DNS 는 kube-dns ClusterIP(서비스 CIDR)로 나간다 — branch ENI 의 SG 평가가 DNAT 이전이라
  # VPC CIDR 만 허용하면 SGP 파드의 모든 DNS 가 행에 걸린다 (실측: STS/DynamoDB 전부 불통 → 8-2 504)
  egress {
    description = "CoreDNS lookup (TCP)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.cluster_service_cidr]
  }

  egress {
    description = "CoreDNS lookup (UDP)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr, var.cluster_service_cidr]
  }

  tags = { Name = "${var.name_prefix}-book-pod-sg" }
}
