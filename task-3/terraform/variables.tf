# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# S3 버킷 이름은 전역 유일이라 안전한 default가 없다 → default 없이 두어
# terraform.tfvars 누락 시 apply가 즉시 실패하게 한다.
variable "bucket_name" {
  description = "product 이미지 S3 버킷 이름"
  type        = string
}

# ── 앱 목록: ECR 레포가 이 목록에서 생성된다.
# 레포명 = k8s 매니페스트 이미지명 (정확 일치 필수).
# ALB 경로·포트·헬스체크는 k8s/20-ingress.yaml로 옮겼다 —
# 당일 API 추가/삭제 = 여기 한 줄 + k8s/1X-<app>.yaml + Ingress 경로 한 블록.
variable "apps" {
  type    = list(string)
  default = ["user", "product", "stress"]
}

variable "image_tag" {
  description = "컨테이너 이미지 태그"
  type        = string
  default     = "v1"
}

variable "db_password" {
  description = "RDS master 비밀번호"
  type        = string
  sensitive   = true
}
