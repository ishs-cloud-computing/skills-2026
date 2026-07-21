# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 실행별 입력 + 당일 변경 1순위 값(앱 목록·이미지 태그)만 변수로 둔다.
# 나머지 과제 상수(이름·CIDR·DB 사양)는 locals.tf.
variable "player_number" {
  description = "대회 비번호"
  type        = string
}

# ── 앱 목록: ECR 레포·ALB 타깃그룹·리스너 규칙이 전부 이 맵에서 생성된다.
# 레포명 = 맵 키 = k8s 매니페스트 이미지명 (정확 일치 필수).
# 당일 API 추가/삭제 = 여기 한 항목 + k8s/1X-<app>.yaml 복사/삭제.
# path는 ALB 경로 규칙, priority는 규칙 우선순위.
variable "apps" {
  type = map(object({
    path        = string
    priority    = number
    port        = number
    health_path = string
  }))
  default = {
    user    = { path = "/v1/user", priority = 10, port = 8080, health_path = "/healthcheck" }
    product = { path = "/v1/product", priority = 20, port = 8080, health_path = "/healthcheck" }
    stress  = { path = "/v1/stress", priority = 30, port = 8080, health_path = "/healthcheck" }
  }
}

variable "image_tag" {
  description = "컨테이너 이미지 태그. 빌드/푸시(README STEP 4)와 k8s 치환(STEP 8)이 모두 이 값을 따른다."
  type        = string
  default     = "v1"
}

variable "db_password" {
  description = "RDS master 비밀번호"
  type        = string
  sensitive   = true
  default     = "password"
}
