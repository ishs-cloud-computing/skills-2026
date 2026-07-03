# ---------------------------------------------------------------------------
# VPC Endpoints
# app(private) 서브넷에 AZ별 NAT 가 있으므로 Interface Endpoint 는 만들지 않는다
# (과제에 프라이빗 통신 요구 없음 — 비용·생성 시간 절감).
# S3 Gateway Endpoint 만 두어 ECR 이미지 레이어 풀을 NAT 미경유로 안정화한다.
#
# 주의: eks / eks-auth Interface Endpoint 를 private_dns_enabled 로 만들면
# PHZ 가 OIDC/eks-auth 도메인 해석을 가로채 Pod Identity/IRSA 가 깨질 수 있다
# (set-05 트러블슈팅). fully private 클러스터여도 NAT 경유 호출로 충분하다.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for k in local.private_subnet_keys : aws_route_table.app[k].id]

  tags = { Name = "wsc2026-vpce-s3" }
}
