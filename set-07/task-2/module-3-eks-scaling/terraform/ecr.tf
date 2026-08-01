# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ECR (과제지 3-3: app.py 컨테이너 이미지 배포)
# - 대회 PC 는 Docker 불가 → CloudShell 에서 build/push (README 런북 3단계).
# - force_delete: destroy 시 이미지가 남아 있어도 저장소 삭제.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name         = var.ecr_repo_name
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = var.ecr_repo_name }
}
