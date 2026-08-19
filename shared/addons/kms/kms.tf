# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# KMS CMK 부착 스니펫 — set-XX/task-1/terraform/ 으로 복사해 사용
# 원본: set-07 task-1 kms.tf (서비스별 key policy 확장은 그쪽 참고)
# 대상 리소스에 붙이는 패턴은 ./README.md 의 "부착 패턴" 절.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_kms" {}

# 계정 root 전체 권한 — 이 문장이 없으면 키 관리 자체가 잠긴다.
# 서비스 principal(logs·autoscaling·cloudfront) 확장이 필요하면 set-07 kms.tf 의
# kms_platform / kms_data 정책 문장을 이 document 에 추가한다.
data "aws_iam_policy_document" "addon_kms_root" {
  statement {
    sid       = "EnableRoot"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.addon_kms.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "addon" {
  description             = var.addon_kms_description
  enable_key_rotation     = true
  rotation_period_in_days = var.addon_kms_rotation_days
  # 대회 계정은 대회 후 폐기되지만, 잘못 만든 키를 당일 지우고 다시 만들 수 있게 최소값을 쓴다.
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.addon_kms_root.json
}

resource "aws_kms_alias" "addon" {
  name          = "alias/${var.addon_kms_alias}"
  target_key_id = aws_kms_key.addon.key_id
}
