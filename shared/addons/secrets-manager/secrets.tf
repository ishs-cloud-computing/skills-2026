# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Secrets Manager 부착 스니펫 — 시크릿(JSON) + 읽기 정책 + 회전(선택)
# 원본: set-08 task-2 module-1-nosql secrets.tf (DocDB 접속 정보 JSON)
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "addon" {
  name       = var.addon_secret_name
  kms_key_id = var.addon_secret_kms_key_arn == "" ? null : var.addon_secret_kms_key_arn
  # 0 이면 즉시 삭제 — teardown 뒤 같은 이름으로 바로 재생성 가능 (7~30 이면 그 기간 이름이 잠긴다)
  recovery_window_in_days = var.addon_secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "addon" {
  secret_id     = aws_secretsmanager_secret.addon.id
  secret_string = jsonencode(var.addon_secret_values)
}

# 읽기 최소 권한. CMK 를 쓰면 Decrypt 가 없을 때 GetSecretValue 가 AccessDenied 로 실패한다.
data "aws_iam_policy_document" "addon_secret_read" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.addon.arn]
  }

  dynamic "statement" {
    for_each = var.addon_secret_kms_key_arn == "" ? [] : [1]
    content {
      actions   = ["kms:Decrypt"]
      resources = [var.addon_secret_kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "addon_secret_read" {
  name   = var.addon_secret_read_policy_name
  policy = data.aws_iam_policy_document.addon_secret_read.json
}

resource "aws_iam_role_policy_attachment" "addon_secret_read" {
  for_each = toset(var.addon_secret_reader_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.addon_secret_read.arn
}

# ----- 회전 (addon_secret_rotation_lambda_arn 이 비어 있으면 생성 안 함) -----
# Secrets Manager 가 Lambda 를 호출하려면 함수 리소스 정책이 필요하다 — 없으면 회전 설정 자체가 거부된다.
resource "aws_lambda_permission" "addon_secret_rotation" {
  count = var.addon_secret_rotation_lambda_arn == "" ? 0 : 1

  statement_id  = "AllowSecretsManagerInvoke-${var.addon_secret_name}"
  action        = "lambda:InvokeFunction"
  function_name = var.addon_secret_rotation_lambda_arn
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.addon.arn
}

resource "aws_secretsmanager_secret_rotation" "addon" {
  count = var.addon_secret_rotation_lambda_arn == "" ? 0 : 1

  secret_id           = aws_secretsmanager_secret.addon.id
  rotation_lambda_arn = var.addon_secret_rotation_lambda_arn
  # 기본 true 면 apply 즉시 회전을 한 번 돌린다 — 회전 Lambda 가 미완성이면 apply 가 실패한다.
  rotate_immediately = var.addon_secret_rotate_immediately

  rotation_rules {
    automatically_after_days = var.addon_secret_rotation_days
  }

  depends_on = [aws_lambda_permission.addon_secret_rotation, aws_secretsmanager_secret_version.addon]
}
