# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC Endpoints (요구사항 3)
# App(private) 의 "컨테이너 이미지 다운로드 및 로그/메트릭 export" 는 외부 인터넷을
# 경유하지 않아야 한다. private 서브넷에 NAT 가 있어도 아래 서비스는 private DNS 가
# Interface/Gateway Endpoint 로 해석되어 엔드포인트(ENI/PrivateLink)로만 통신한다.
# - S3        : Gateway Endpoint (private RTB 연결, 라우트는 prefix-list 라 0.0.0.0/0 무영향)
# - ecr.api / ecr.dkr / logs : Interface Endpoint (private DNS)
# (mark 1-3-A: s3 / ecr.api / ecr.dkr 존재 확인)
# ---------------------------------------------------------------------------

# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for k in local.private_subnet_keys : aws_route_table.private[k].id]

  tags = { Name = "unicorn-vpce-s3" }
}

locals {
  interface_endpoints = ["ecr.api", "ecr.dkr", "logs"]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "unicorn-vpce-${each.key}" }
}
