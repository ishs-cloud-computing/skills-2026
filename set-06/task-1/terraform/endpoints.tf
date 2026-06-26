# ---------------------------------------------------------------------------
# VPC Interface Endpoints (PrivateLink)
# Private 라우트 테이블에는 local 라우트만 있어야 하므로(채점 1-2), Gateway
# Endpoint(S3/DynamoDB) 대신 모든 AWS 서비스 통신을 Interface Endpoint(ENI) 로
# 처리한다. ENI 기반이라 라우트 테이블이 비어 있어도 통신이 가능하다.
#
# - S3 인터페이스 EP 는 Native Private DNS 활성화 시 S3 Gateway EP 를 요구(라우트 추가)
#   하므로 private_dns_enabled=false + Route53 Private Hosted Zone 으로 매핑한다.
# - DynamoDB 인터페이스 EP 는 Private DNS 를 제공하지 않으므로 동일하게 PHZ 매핑.
# - eks/eks-auth EP 는 생성하지 않는다(private DNS PHZ 가 oidc.eks.* 조회를 가로채
#   IRSA 를 파괴). 클러스터 endpointPublicAccess=true 라 CloudShell 에서 kubectl 동작.
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  name        = "gj2026-vpce-sg"
  description = "Allow HTTPS from VPC to interface endpoints"
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

  tags = { Name = "gj2026-vpce-sg" }
}

locals {
  # Native Private DNS 를 지원하는 서비스 (기본 도메인으로 해석됨)
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",       # Fluent Bit / Lambda 로그
    "monitoring", # Lambda PutMetricData + Grafana CloudWatch 데이터소스 조회
    "ec2",
    "elasticloadbalancing",
    "autoscaling",
    "kms",
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "gj2026-vpce-${each.key}" }
}

# ----- S3 / DynamoDB: Interface Endpoint (Private DNS 비활성) -----
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = false

  tags = { Name = "gj2026-vpce-s3" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = false

  tags = { Name = "gj2026-vpce-dynamodb" }
}

# ----- Route53 Private Hosted Zone 으로 기본 도메인을 인터페이스 EP 로 매핑 -----
resource "aws_route53_zone" "s3" {
  name = "s3.${var.region}.amazonaws.com"
  vpc {
    vpc_id = aws_vpc.this.id
  }
  comment = "gj2026 - resolve S3 to interface endpoint"
}

resource "aws_route53_record" "s3_apex" {
  zone_id = aws_route53_zone.s3.zone_id
  name    = "s3.${var.region}.amazonaws.com"
  type    = "A"
  alias {
    name                   = aws_vpc_endpoint.s3.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.s3.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# 가상 호스팅 방식(bucket.s3.region.amazonaws.com) 대응 와일드카드
resource "aws_route53_record" "s3_wildcard" {
  zone_id = aws_route53_zone.s3.zone_id
  name    = "*.s3.${var.region}.amazonaws.com"
  type    = "A"
  alias {
    name                   = aws_vpc_endpoint.s3.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.s3.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "dynamodb" {
  name = "dynamodb.${var.region}.amazonaws.com"
  vpc {
    vpc_id = aws_vpc.this.id
  }
  comment = "gj2026 - resolve DynamoDB to interface endpoint"
}

resource "aws_route53_record" "dynamodb_apex" {
  zone_id = aws_route53_zone.dynamodb.zone_id
  name    = "dynamodb.${var.region}.amazonaws.com"
  type    = "A"
  alias {
    name                   = aws_vpc_endpoint.dynamodb.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.dynamodb.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}
