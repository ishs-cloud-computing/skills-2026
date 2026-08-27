# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# latest 태그 재푸시가 필요하므로 MUTABLE 필수
resource "aws_ecr_repository" "book" {
  name                 = local.ecr_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    Name = local.ecr_name
  }
}
