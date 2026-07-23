# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ECR (과제지 3. EKS Scaling - 3. Application)
# - 제공 app.py/Dockerfile(수정 금지)을 bastion 에서 빌드해 푸시한다 (README).
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name         = var.ecr_repo_name
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = var.ecr_repo_name }
}
