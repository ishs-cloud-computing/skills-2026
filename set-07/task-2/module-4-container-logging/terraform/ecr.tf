# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ECR (과제지 4-2. Log Producer Application)
# - 제공 app.py + 자체 Dockerfile(app/)로 bastion 에서 빌드해 푸시한다 (README).
#   제공 Dockerfile 은 flask 를 설치하지 않아 그대로는 기동 불가 → app/Dockerfile 사용.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name         = var.ecr_repo_name
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = var.ecr_repo_name }
}
