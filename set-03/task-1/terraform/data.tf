data "aws_caller_identity" "current" {}

# assumed-role 세션이면 기반 role ARN 을, IAM user 면 user ARN 을 돌려준다.
# KMS 키 정책의 관리자 principal 로 사용 (유의사항 10: root 금지).
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# CloudFront 의 origin-facing 관리형 prefix list
# (wsc2026-app-alb 는 CloudFront 에서만 인입 허용 — 요구사항 12)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # 요구사항 9: wsc2026-static-<임의의 영문 4자리>-<본인 비번호>-bucket
  bucket_name = "wsc2026-static-${var.bucket_suffix}-${var.player_number}-bucket"

  public_subnet_keys  = [for k, v in var.subnets : k if v.tier == "public"]
  private_subnet_keys = [for k, v in var.subnets : k if v.tier == "private"]

  public_subnet_ids  = [for k in local.public_subnet_keys : aws_subnet.this[k].id]
  private_subnet_ids = [for k in local.private_subnet_keys : aws_subnet.this[k].id]

  # 본 클러스터 ARN (Pod Identity trust 한정에 사용)
  cluster_arn = "arn:aws:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"

  # KMS 키 관리자 principal (배포자 + 추가 관리자).
  # 유의사항 10: 키 정책에 root principal 금지 → 배포 자격증명이 계정 root 면
  # 목록에서 제외한다 (이 경우 kms_extra_admin_arns 로 IAM 신원을 반드시 지정).
  issuer_is_root = endswith(data.aws_iam_session_context.current.issuer_arn, ":root")
  kms_admin_arns = concat(
    local.issuer_is_root ? [] : [data.aws_iam_session_context.current.issuer_arn],
    var.kms_extra_admin_arns,
  )
}

# KMS 키 정책에 들어갈 관리자가 하나도 없으면 (root 자격증명 + 미지정) plan 단계에서 차단.
resource "terraform_data" "kms_admin_guard" {
  lifecycle {
    precondition {
      condition     = length(local.kms_admin_arns) > 0
      error_message = "root 자격증명으로는 KMS 키 정책을 구성할 수 없습니다 (유의사항 10: root 금지). IAM 사용자/역할 자격증명으로 실행하거나 kms_extra_admin_arns 에 IAM principal ARN 을 지정하세요."
    }
  }
}
