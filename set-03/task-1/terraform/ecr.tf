# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ECR (요구사항 6)
# - wsc2026-book-ecr : scan on push, ecr CMK 암호화
# - 같은 태그 재업로드 허용하되 v1* 태그는 예외(불변) → MUTABLE_WITH_EXCLUSION
#   (provider 6.8.0+ 필요)
# - 이미지는 v1.0.0 단일 태그만 존재해야 함 → push 시 latest 금지 (README 런북)
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "book" {
  name         = var.ecr_name
  force_delete = true

  image_tag_mutability = "MUTABLE_WITH_EXCLUSION"
  image_tag_mutability_exclusion_filter {
    filter      = "v1*"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = { Name = var.ecr_name }
}