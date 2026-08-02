# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# worker 컨테이너 이미지 저장소 (과제지 6-5 — 이미지 직접 작성.
# 빌드·푸시는 CloudShell 에서 수행, README 3단계)
resource "aws_ecr_repository" "worker" {
  name         = var.ecr_repo_name
  force_delete = true
}
