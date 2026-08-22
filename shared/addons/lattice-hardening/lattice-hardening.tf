# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# VPC Lattice 하드닝 부착 스니펫 — IAM auth policy · 액세스 로그 · 헤더 기반 리스너 룰.
# 기존 리소스 안에 넣는 인자(auth_type·association SG·TG 타입·서비스 SG)는 README "블록" 절.
# 원본: set-05 task-2 module-2-vpc-lattice lattice.tf, set-08 task-2 module-2-lattice lattice.tf·sg.tf
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_lattice" {}

# ----- IAM auth policy (서비스 auth_type = "AWS_IAM" 필요 — README 블록) -----
# auth_type 만 AWS_IAM 으로 바꾸고 정책이 없으면 모든 요청이 403 이다.
data "aws_iam_policy_document" "addon_lattice_auth" {
  statement {
    effect    = "Allow"
    actions   = ["vpc-lattice-svcs:Invoke"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = length(var.addon_lattice_auth_principal_arns) > 0 ? var.addon_lattice_auth_principal_arns : ["*"]
    }

    dynamic "condition" {
      for_each = length(var.addon_lattice_auth_principal_arns) > 0 ? [] : [1]
      content {
        test     = "StringEquals"
        variable = "aws:PrincipalAccount"
        values   = [data.aws_caller_identity.addon_lattice.account_id]
      }
    }
  }
}

resource "aws_vpclattice_auth_policy" "addon" {
  resource_identifier = var.addon_lattice_service_id
  policy              = data.aws_iam_policy_document.addon_lattice_auth.json
}

# ----- 액세스 로그 (CloudWatch Logs 기본, S3 선택) -----
resource "aws_cloudwatch_log_group" "addon_lattice" {
  name              = "/aws/vpclattice/${var.addon_lattice_service_name}"
  retention_in_days = var.addon_lattice_log_retention_days
}

resource "aws_vpclattice_access_log_subscription" "addon_cw" {
  resource_identifier = var.addon_lattice_service_id
  destination_arn     = aws_cloudwatch_log_group.addon_lattice.arn
}

resource "aws_vpclattice_access_log_subscription" "addon_s3" {
  count               = var.addon_lattice_log_s3_bucket_arn == "" ? 0 : 1
  resource_identifier = var.addon_lattice_service_id
  destination_arn     = var.addon_lattice_log_s3_bucket_arn
}

# ----- 헤더 기반 리스너 룰: version=v1 → v1 TG, version=v2 → v2 TG -----
# 가중(기본) 라우팅은 리스너 default_action 에 둔다 (README 블록). priority 가 낮을수록 먼저 평가.
locals {
  addon_lattice_rules_enabled = var.addon_lattice_listener_id != ""
  addon_lattice_header_rules = local.addon_lattice_rules_enabled ? {
    v1 = { tg = var.addon_lattice_v1_target_group_id, priority = var.addon_lattice_rule_priority_base }
    v2 = { tg = var.addon_lattice_v2_target_group_id, priority = var.addon_lattice_rule_priority_base + 10 }
  } : {}
}

resource "aws_vpclattice_listener_rule" "addon_header" {
  for_each = local.addon_lattice_header_rules

  name                = "${var.addon_lattice_header_name}-${each.key}"
  listener_identifier = var.addon_lattice_listener_id
  service_identifier  = var.addon_lattice_service_id
  priority            = each.value.priority

  match {
    http_match {
      header_matches {
        name           = var.addon_lattice_header_name
        case_sensitive = false
        match {
          exact = each.key
        }
      }
    }
  }

  action {
    forward {
      target_groups {
        target_group_identifier = each.value.tg
        weight                  = 100
      }
    }
  }
}
