# ---------------------------------------------------------------------------
# Security Groups
# - MSK SG 인바운드는 표준 규칙 리소스로 분리: 클라이언트 SG(producer/lambda/
#   bastion)를 참조하므로 인라인로 쓰면 순환 참조가 된다.
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
    bastion  = aws_security_group.bastion.id
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

# ----- Producer EC2 (프라이빗 — 인바운드 없음, SSM 접속) -----

resource "aws_security_group" "producer" {
  name        = "wsc2026-producer-sg"
  description = "sensor producer - no inbound"
  vpc_id      = aws_vpc.msk.id

  egress {
    description = "HTTP outbound (anyopen - task rule 6)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS outbound (anyopen - task rule 6, SSM/S3)"
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

  tags = { Name = "wsc2026-producer-sg" }
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

# ----- Bastion (mark 실행·kafka 디버깅) -----

resource "aws_security_group" "bastion" {
  name        = "wsc2026-msk-bastion-sg"
  description = "Bastion - allow SSH inbound only"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc2026-msk-bastion-sg" }
}
