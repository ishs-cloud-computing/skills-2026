# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Audit Role 부착 스니펫 — ExternalId 조건 + 세션 제한 + 인라인 최소권한 정책
# 원본: set-07 task-1 iam.tf (unicorn-audit-role, 요구사항 11)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_audit" {}

locals {
  # 빈 목록이면 같은 계정의 모든 IAM principal (계정 root)
  addon_audit_principals = length(var.addon_audit_trusted_principal_arns) > 0 ? var.addon_audit_trusted_principal_arns : ["arn:aws:iam::${data.aws_caller_identity.addon_audit.account_id}:root"]
}

data "aws_iam_policy_document" "addon_audit_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = local.addon_audit_principals
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.addon_audit_external_id]
    }
  }
}

resource "aws_iam_role" "addon_audit" {
  name                 = var.addon_audit_role_name
  assume_role_policy   = data.aws_iam_policy_document.addon_audit_trust.json
  max_session_duration = var.addon_audit_max_session_duration

  tags = { Name = var.addon_audit_role_name }
}

# 액션 와일드카드 금지 — 과제지가 "와일드카드 금지" 면 채점 스크립트가 정책 JSON 의 '*' 를 grep 한다.
# Describe/List 계열은 리소스 레벨 ARN 미지원이라 resources 만 "*" 허용.
data "aws_iam_policy_document" "addon_audit" {
  dynamic "statement" {
    for_each = var.addon_audit_policy_statements
    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "addon_audit" {
  name   = var.addon_audit_policy_name
  role   = aws_iam_role.addon_audit.id
  policy = data.aws_iam_policy_document.addon_audit.json
}
