# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ECR (요구사항 7)
# - unicorn-concert-app : scan on push, Data CMK 암호화
# - latest 를 제외한 태그 중복 불허 → IMMUTABLE_WITH_EXCLUSION (latest 제외)
#   (provider 6.8.0+ 필요)
# - 이미지 태그: v1.0.0, latest (push 는 README 런북 참조, 취약점 0)
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name         = "unicorn-concert-app"
  force_delete = true

  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
  image_tag_mutability_exclusion_filter {
    filter      = "latest"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data.arn
  }

  tags = { Name = "unicorn-concert-app" }
}
