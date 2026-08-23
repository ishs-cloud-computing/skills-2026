# ---------------------------------------------------------------------------
# Security Groups
# - MSK SG 인바운드는 표준 규칙 리소스로 분리: 클라이언트 SG(producer/lambda)를
#   참조하므로 인라인로 쓰면 순환 참조가 된다.
# - MSK SG 셀프 참조 전체 허용: 브로커 간·ZooKeeper 통신 + Lambda ESM 폴러 ENI
#   (ESM 은 클러스터의 서브넷/SG 를 그대로 사용) 모두 이 SG 안에서 일어난다.
# - 클라이언트 → MSK 는 9098 (SASL/IAM 리스너 포트)
# ---------------------------------------------------------------------------

resource "aws_security_group" "msk" {
  name        = "wsc2026-msk-sg"
  description = "MSK brokers - IAM clients on 9098"
  vpc_id      = aws_vpc.msk.id

  tags = { Name = "wsc2026-msk-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "msk_self" {
  security_group_id            = aws_security_group.msk.id
  description                  = "broker/ZK/ESM intra-cluster"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.msk.id
}

resource "aws_vpc_security_group_egress_rule" "msk_all" {
  security_group_id = aws_security_group.msk.id
  description       = "cluster outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

locals {
  msk_client_sgs = {
    producer = aws_security_group.producer.id
    lambda   = aws_security_group.lambda.id
  }
}

resource "aws_vpc_security_group_ingress_rule" "msk_iam_clients" {
  for_each = local.msk_client_sgs

  security_group_id            = aws_security_group.msk.id
  description                  = "SASL/IAM from ${each.key}"
  from_port                    = 9098
  to_port                      = 9098
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
}

# tls 모드에서만 존재한다. 제공 app 바이너리는 IAM 불가·9094 전용 TLS 라 producer 에게만
# 비인증 리스너를 열어 준다. 기본 iam 모드엔 9094 리스너 자체가 없어 규칙도 만들지 않는다.
resource "aws_vpc_security_group_ingress_rule" "msk_tls_producer" {
  count = var.producer_auth_mode == "tls" ? 1 : 0

  security_group_id            = aws_security_group.msk.id
  description                  = "TLS (unauthenticated) from producer app"
  from_port                    = 9094
  to_port                      = 9094
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.producer.id
}

# ----- Producer EC2 (프라이빗 — 인바운드 없음, SSM 접속) -----
# egress 는 표준 규칙 리소스로 분리: 9094 규칙이 tls 모드에서만 존재해야 하는데
# (count) 인라인 블록은 count 를 못 쓰고, 인라인·표준 리소스 혼용은 서로 규칙을
# 지우는 충돌을 낳는다.

resource "aws_security_group" "producer" {
  name        = "wsc2026-producer-sg"
  description = "sensor producer - no inbound"
  vpc_id      = aws_vpc.msk.id

  tags = { Name = "wsc2026-producer-sg" }
}

resource "aws_vpc_security_group_egress_rule" "producer_http" {
  security_group_id = aws_security_group.producer.id
  description       = "HTTP outbound (anyopen - task rule 6)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "producer_https" {
  security_group_id = aws_security_group.producer.id
  description       = "HTTPS outbound (anyopen - task rule 6, SSM/S3)"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "producer_msk_iam" {
  security_group_id            = aws_security_group.producer.id
  description                  = "Kafka SASL/IAM to MSK"
  from_port                    = 9098
  to_port                      = 9098
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.msk.id
}

# MSK 쪽 9094 인바운드(msk_tls_producer)와 대칭 — iam 모드엔 9094 리스너가 없어
# 규칙만 남으면 불필요 오픈 포트가 된다.
resource "aws_vpc_security_group_egress_rule" "producer_msk_tls" {
  count = var.producer_auth_mode == "tls" ? 1 : 0

  security_group_id            = aws_security_group.producer.id
  description                  = "Kafka TLS to MSK (app binary)"
  from_port                    = 9094
  to_port                      = 9094
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.msk.id
}

# ----- Lambda sensor-consumer (VPC 내 — alert 토픽 produce 용) -----

resource "aws_security_group" "lambda" {
  name        = "wsc2026-msk-lambda-sg"
  description = "sensor-consumer lambda in VPC"
  vpc_id      = aws_vpc.msk.id

  egress {
    description = "HTTPS outbound (DynamoDB via NAT)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Kafka SASL/IAM to MSK"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.msk.id]
  }

  tags = { Name = "wsc2026-msk-lambda-sg" }
}
