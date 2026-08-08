# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 레포명 = var.apps 항목 = k8s 매니페스트 이미지명. 태그는 var.image_tag.
resource "aws_ecr_repository" "app" {
  for_each = local.apps

  name         = each.key
  force_delete = true
}
