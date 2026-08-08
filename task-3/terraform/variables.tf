# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 실행별 입력 + 당일 변경 1순위 값(앱 목록·이미지 태그)만 변수로 둔다.
# 나머지 과제 상수(이름·CIDR·DB 사양)는 locals.tf.

# S3 버킷 이름은 전역 유일이라 안전한 default가 없다 → default 없이 두어
# terraform.tfvars 누락 시 apply가 즉시 실패하게 한다.
variable "bucket_name" {
  description = "product 이미지 S3 버킷 이름 (전역 유일)"
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
  description = "컨테이너 이미지 태그. 빌드/푸시(README STEP 3)와 k8s 치환(STEP 6)이 모두 이 값을 따른다."
  type        = string
  default     = "v1"
}

# default을 두지 않는다 — 값이 terraform.tfvars 한 곳에만 존재하게 해서
# 셸 환경변수와 어긋나는 사고를 없앤다(앱 매니페스트 치환은 output으로 흘러간다).
variable "db_password" {
  description = "RDS master 비밀번호"
  type        = string
  sensitive   = true
}
