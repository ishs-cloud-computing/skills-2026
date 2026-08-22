# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# 클라이언트 EC2 — private 서브넷, SSM 접속, mysql 클라이언트 + 연결 테스트 스크립트.
# 원본: set-08 task-2 module-1 ec2.tf·iam.tf 범용화.
# Proxy 가 켜져 있으면 Proxy 엔드포인트로, 아니면 인스턴스 엔드포인트로 붙는다.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "addon_rds_al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_region" "addon_rds" {}
data "aws_caller_identity" "addon_rds" {}

data "aws_iam_policy_document" "addon_rds_ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_rds_client" {
  name               = "${var.addon_rds_client_ec2_name}-role"
  assume_role_policy = data.aws_iam_policy_document.addon_rds_ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "addon_rds_client_ssm" {
  role       = aws_iam_role.addon_rds_client.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# GetSecretValue 는 이 Secret 하나로 한정. rds-db:connect 는 IAM 인증을 켰을 때만.
data "aws_iam_policy_document" "addon_rds_client" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.addon_rds.arn]
  }

  dynamic "statement" {
    for_each = var.addon_rds_iam_auth || var.addon_rds_proxy_iam_auth ? [1] : []
    content {
      actions = ["rds-db:connect"]
      resources = concat(
        ["arn:aws:rds-db:${data.aws_region.addon_rds.region}:${data.aws_caller_identity.addon_rds.account_id}:dbuser:${aws_db_instance.addon.resource_id}/*"],
        var.addon_rds_proxy_enabled ? ["arn:aws:rds-db:${data.aws_region.addon_rds.region}:${data.aws_caller_identity.addon_rds.account_id}:dbuser:${aws_db_proxy.addon[0].id}/*"] : [],
      )
    }
  }
}

resource "aws_iam_role_policy" "addon_rds_client" {
  name   = "${var.addon_rds_client_ec2_name}-policy"
  role   = aws_iam_role.addon_rds_client.id
  policy = data.aws_iam_policy_document.addon_rds_client.json
}

resource "aws_iam_instance_profile" "addon_rds_client" {
  name = "${var.addon_rds_client_ec2_name}-profile"
  role = aws_iam_role.addon_rds_client.name
}

resource "aws_instance" "addon_rds_client" {
  ami                    = data.aws_ssm_parameter.addon_rds_al2023.value
  instance_type          = var.addon_rds_client_instance_type
  subnet_id              = values(aws_subnet.addon_rds_private)[0].id
  vpc_security_group_ids = [aws_security_group.addon_rds_client.id]
  iam_instance_profile   = aws_iam_instance_profile.addon_rds_client.name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    region      = data.aws_region.addon_rds.region
    secret_name = var.addon_rds_secret_name
    db_host     = var.addon_rds_proxy_enabled ? aws_db_proxy.addon[0].endpoint : aws_db_instance.addon.address
    db_port     = var.addon_rds_port
  })

  tags = { Name = var.addon_rds_client_ec2_name }

  # user-data 의 dnf 가 NAT 없이는 실패한다
  depends_on = [aws_route.addon_rds_private_default]
}
