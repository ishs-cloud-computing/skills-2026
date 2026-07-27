# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# 작업용 bastion (채점 대상 아님 — 배포 작업 환경)
# 클러스터가 fully private 라 본 PC 에서 kubectl 이 닿지 않는다. VPC CloudShell 은
# 홈이 세션마다 삭제되고 업로드 UI 도 없어 중간 수정이 비싸므로, 홈이 유지되는
# bastion 에서 k8s 작업을 한다. 채점 전 enable_bastion=false 로 제거한다.
#
# - SG 는 mark-sg 재사용: eks-cp-extra-sg 가 이미 mark-sg → private API 443 을 허용한다.
#   새 SG·새 CP 인그레스가 0개이고, 채점자가 쓸 경로를 배포 내내 검증하게 된다.
# - app(private) 서브넷 배치: SSM·kubectl/helm 다운로드가 NAT 로 해결되어 Interface
#   Endpoint 가 필요 없다 (endpoints.tf 의 "S3 Gateway 만 둔다" 결정과 충돌하지 않음).
# - 접속은 SSM Session Manager → 인바운드 규칙 0개, public IP·EIP·SSH 불필요.
# - EKS 권한은 인스턴스 역할이 아니라 bastion 에서 aws configure 한 wsc2026-admin 이 갖는다
#   (cluster.yaml bootstrapClusterCreatorAdminPermissions=true 이므로 access entry 불필요).
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_policy_document" "bastion_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  count              = var.enable_bastion ? 1 : 0
  name               = "${var.name_prefix}-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.bastion_assume.json
}

# SSM 접속에 필요한 최소 권한만. AWS 작업 권한은 aws configure 로 받는다.
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  count      = var.enable_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  count = var.enable_bastion ? 1 : 0
  name  = "${var.name_prefix}-bastion-profile"
  role  = aws_iam_role.bastion[0].name
}

resource "aws_instance" "bastion" {
  count = var.enable_bastion ? 1 : 0

  ami           = data.aws_ssm_parameter.al2023.value
  instance_type = var.bastion_instance_type
  # 채점 CloudShell 과 같은 서브넷(app-sub-a). private_subnet_keys 는 var.subnets 키의
  # 사전순이라 [0] 이 app-sub-a 이고, 이름이 바뀌어도 따라간다.
  subnet_id              = local.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.mark.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion[0].name
  user_data              = file("${path.module}/bastion_user_data.sh")

  metadata_options {
    http_tokens = "required" # IMDSv2 강제
  }

  root_block_device {
    encrypted = true # aws configure 자격증명이 올라가므로 암호화
  }

  # NAT 준비 전에 부팅하면 user_data 의 curl 이 실패한다
  depends_on = [aws_route_table_association.app]

  tags = { Name = "${var.name_prefix}-bastion" }
}
