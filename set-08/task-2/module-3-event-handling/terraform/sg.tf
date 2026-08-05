# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# 보호 대상 Security Group (과제지 5-1, 채점 3-2)
# - Inbound 규칙 0개가 기준 상태 — ingress 를 terraform 으로 만들지 않는다.
#   채점 3-5 가 임시 추가하는 TCP/22 는 Lambda 가 복구하므로 state 밖 —
#   ingress 규칙 리소스를 선언하지 않아 drift 도 발생하지 않는다.
# - egress 는 AWS 기본(allow all)을 별도 규칙 리소스로 유지.
# ---------------------------------------------------------------------------

resource "aws_security_group" "protected" {
  name        = var.protected_sg_name
  description = "protected sg - inbound must stay empty"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = var.protected_sg_name }
}

resource "aws_vpc_security_group_egress_rule" "protected_all" {
  security_group_id = aws_security_group.protected.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "all outbound"
}
