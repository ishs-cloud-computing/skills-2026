# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# EC2 2대 (과제지 4-2·4-3). 지급 앱 원본을 base64 로 user-data 임베드
# (provided/ 무수정). client 의 SERVICE_URL 은 Lattice service 의 generated
# domain 을 terraform 참조로 주입 — 의존성 순서 자동 해결.
# 대가: 도메인 변경 시 user_data 변경으로 client 인스턴스 재생성.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "service" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.service.id
  vpc_security_group_ids = [aws_security_group.service.id]

  user_data = templatefile("${path.module}/userdata-service.sh.tftpl", {
    app_b64 = base64encode(file("${path.module}/../../provided/module-2/service_app.py"))
  })

  tags = { Name = var.service_ec2_name }
}

resource "aws_instance" "client" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.client.id
  vpc_security_group_ids = [aws_security_group.client.id]

  user_data = templatefile("${path.module}/userdata-client.sh.tftpl", {
    app_b64     = base64encode(file("${path.module}/../../provided/module-2/client_app.py"))
    service_url = "http://${aws_vpclattice_service.order.dns_entry[0].domain_name}"
  })

  tags = { Name = var.client_ec2_name }
}
