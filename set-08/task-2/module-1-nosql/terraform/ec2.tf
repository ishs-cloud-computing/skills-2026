# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Client EC2 (과제지 3-1, 채점 1-2·1-3)
# - 지급 앱·데이터셋 원본을 gzip+base64 로 user-data 임베드 (provided/ 무수정).
#   두 파일 평문 base64 는 user-data 16KB 한도를 넘어 base64gzip() 사용.
# - depends_on 으로 DocumentDB 인스턴스 가용 이후 부팅 — user-data 의
#   seed/index 재시도 루프가 짧게 끝난다.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "client" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.client.id]
  iam_instance_profile   = aws_iam_instance_profile.client.name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    app_gz_b64     = base64gzip(file("${path.module}/../../provided/module-1/docdb_client.py"))
    dataset_gz_b64 = base64gzip(file("${path.module}/../../provided/module-1/retail_dataset.json"))
    index_gz_b64 = base64gzip(templatefile("${path.module}/index_setup.py.tftpl", {
      region      = var.region
      secret_name = var.secret_name
      docdb_port  = var.docdb_port
    }))
  })

  tags = { Name = var.client_ec2_name }

  depends_on = [
    aws_docdb_cluster_instance.primary,
    aws_secretsmanager_secret_version.docdb,
  ]
}
