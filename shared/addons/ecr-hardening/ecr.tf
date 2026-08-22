# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ECR 하드닝 부착 스니펫 — 기존 리포지토리에 lifecycle policy + pull-through cache
# 원본: set-05 task-1 ecr.tf (pull-through cache). 리포지토리 안 인자(스캔·불변 태그·
# 암호화)는 ./README.md 블록으로 기존 aws_ecr_repository 에 붙인다.
# ---------------------------------------------------------------------------

# tagStatus=any 규칙은 가장 큰 rulePriority 여야 한다(ECR 제약) — untagged 를 1번에 둔다.
resource "aws_ecr_lifecycle_policy" "addon" {
  repository = var.addon_ecr_repository_name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.addon_ecr_untagged_expire_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "keep last N tagged images"
        selection = merge(
          {
            tagStatus   = length(var.addon_ecr_keep_tag_prefixes) == 0 ? "any" : "tagged"
            countType   = "imageCountMoreThan"
            countNumber = var.addon_ecr_keep_image_count
          },
          length(var.addon_ecr_keep_tag_prefixes) == 0 ? {} : { tagPrefixList = var.addon_ecr_keep_tag_prefixes }
        )
        action = { type = "expire" }
      },
    ]
  })
}

# 익명 pull 이 되는 업스트림만 (Docker Hub 는 자격증명 필요 — 대회 규정상 불가).
# prefix 는 계정·리전 내 유일해야 한다 — 이미 있는 세트(set-05 task-1)와 겹치면 tfvars 에서 뺀다.
resource "aws_ecr_pull_through_cache_rule" "addon" {
  for_each = var.addon_ecr_pull_through_upstreams

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value
}
