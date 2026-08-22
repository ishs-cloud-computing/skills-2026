# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Keycloak EC2 — AL2023 + docker + quay.io/keycloak/keycloak (userdata.sh.tpl)
# - admin 비번은 random → Secrets Manager, EC2 가 부팅 시 인스턴스 프로파일로 읽는다
#   (userdata 평문 노출 방지. 원본: set-08 task-2 module-1 secrets.tf)
# - 접근은 SSM 만 (bastion·키페어 없음 — 불필요 리소스 감점 방지)
# ---------------------------------------------------------------------------

data "aws_region" "addon_kc" {}

# AL2023 최신 AMI (보안 항목이라 latest 허용 — CLAUDE.md 작업 규칙 2 예외)
data "aws_ssm_parameter" "addon_kc_al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ----- Secrets Manager -----

resource "random_password" "addon_kc_admin" {
  length  = 20
  special = false
}

resource "random_password" "addon_kc_db" {
  count   = var.addon_kc_rds_enabled ? 1 : 0
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "addon_kc" {
  name                    = var.addon_kc_secret_name
  recovery_window_in_days = 0 # teardown 후 같은 이름으로 즉시 재생성 가능해야 함
}

resource "aws_secretsmanager_secret_version" "addon_kc" {
  secret_id = aws_secretsmanager_secret.addon_kc.id
  secret_string = jsonencode(merge(
    {
      username = var.addon_kc_admin_username
      password = random_password.addon_kc_admin.result
    },
    var.addon_kc_rds_enabled ? { db_password = random_password.addon_kc_db[0].result } : {}
  ))
}

# ----- IAM (SSM + 시크릿 읽기만) -----

data "aws_iam_policy_document" "addon_kc_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_kc" {
  name               = var.addon_kc_role_name
  assume_role_policy = data.aws_iam_policy_document.addon_kc_assume.json
}

resource "aws_iam_role_policy_attachment" "addon_kc_ssm" {
  role       = aws_iam_role.addon_kc.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "addon_kc_secret" {
  statement {
    sid       = "ReadAdminSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.addon_kc.arn]
  }
}

resource "aws_iam_role_policy" "addon_kc_secret" {
  name   = "${var.addon_kc_role_name}-secret"
  role   = aws_iam_role.addon_kc.id
  policy = data.aws_iam_policy_document.addon_kc_secret.json
}

resource "aws_iam_instance_profile" "addon_kc" {
  name = "${var.addon_kc_role_name}-profile"
  role = aws_iam_role.addon_kc.name
}

# ----- Security Group (ALB → EC2 8080 만) -----

resource "aws_security_group" "addon_kc_ec2" {
  name        = "${var.addon_kc_instance_name}-sg"
  description = "Keycloak EC2 - 8080 from ALB only"
  vpc_id      = aws_vpc.addon_kc.id

  ingress {
    description     = "Keycloak HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.addon_kc_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.addon_kc_instance_name}-sg" }
}

# ----- EC2 -----

resource "aws_instance" "addon_kc" {
  ami                    = data.aws_ssm_parameter.addon_kc_al2023.value
  instance_type          = var.addon_kc_instance_type
  subnet_id              = values(aws_subnet.addon_kc_public)[0].id
  vpc_security_group_ids = [aws_security_group.addon_kc_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.addon_kc.name

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    region         = data.aws_region.addon_kc.region
    secret_arn     = aws_secretsmanager_secret.addon_kc.arn
    image          = var.addon_kc_image
    admin_username = var.addon_kc_admin_username
    hostname       = var.addon_kc_hostname
    db_host        = var.addon_kc_rds_enabled ? aws_db_instance.addon_kc[0].address : ""
    db_name        = var.addon_kc_db_name
    db_username    = var.addon_kc_db_username
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.addon_kc_instance_name }

  depends_on = [aws_route.addon_kc_public_default, aws_secretsmanager_secret_version.addon_kc]
}

# ----- RDS PostgreSQL (선택, addon_kc_rds_enabled) -----

resource "aws_security_group" "addon_kc_db" {
  count       = var.addon_kc_rds_enabled ? 1 : 0
  name        = "${var.addon_kc_db_identifier}-sg"
  description = "Keycloak RDS - 5432 from EC2 only"
  vpc_id      = aws_vpc.addon_kc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.addon_kc_ec2.id]
  }

  tags = { Name = "${var.addon_kc_db_identifier}-sg" }
}

# 퍼블릭 서브넷에 두되 publicly_accessible=false — 프라이빗 서브넷을 만들면 그쪽으로 교체
resource "aws_db_subnet_group" "addon_kc" {
  count      = var.addon_kc_rds_enabled ? 1 : 0
  name       = "${var.addon_kc_db_identifier}-subnets"
  subnet_ids = [for s in aws_subnet.addon_kc_public : s.id]
}

resource "aws_db_instance" "addon_kc" {
  count = var.addon_kc_rds_enabled ? 1 : 0

  identifier             = var.addon_kc_db_identifier
  engine                 = "postgres"
  engine_version         = var.addon_kc_db_engine_version
  instance_class         = var.addon_kc_db_instance_class
  allocated_storage      = 20
  db_name                = var.addon_kc_db_name
  username               = var.addon_kc_db_username
  password               = random_password.addon_kc_db[0].result
  db_subnet_group_name   = aws_db_subnet_group.addon_kc[0].name
  vpc_security_group_ids = [aws_security_group.addon_kc_db[0].id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  storage_encrypted      = true
}

# ----- Outputs -----

output "addon_kc_alb_dns" {
  description = "Keycloak 접속 호스트 — http://<이 값>/"
  value       = aws_lb.addon_kc.dns_name
}

output "addon_kc_secret_arn" {
  description = "admin 비번 시크릿 ARN (aws secretsmanager get-secret-value --secret-id)"
  value       = aws_secretsmanager_secret.addon_kc.arn
}

output "addon_kc_tg_arn" {
  description = "TG ARN (describe-target-health 로 healthy 확인)"
  value       = aws_lb_target_group.addon_kc.arn
}

output "addon_kc_instance_id" {
  description = "SSM 세션 대상 인스턴스 ID"
  value       = aws_instance.addon_kc.id
}
