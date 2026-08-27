# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# mark.sh는 Name 태그 ARN의 마지막 세그먼트를 repo명으로 쓰므로 이름=태그로 통일
resource "aws_ecr_repository" "book" {
  name                 = local.ecr_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    Name = local.ecr_name
  }
}
