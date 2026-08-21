# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_ecr_repository_name" {
  description = "lifecycle policy 를 붙일 기존 리포지토리 이름 (aws_ecr_repository.<기존>.name)"
  type        = string
}

variable "addon_ecr_untagged_expire_days" {
  description = "untagged 이미지 만료 일수 (push 후 경과 기준)"
  type        = number
  default     = 1
}

variable "addon_ecr_keep_image_count" {
  description = "유지할 태그 이미지 개수 — 초과분은 오래된 순으로 만료"
  type        = number
  default     = 10
}

variable "addon_ecr_keep_tag_prefixes" {
  description = "유지 규칙을 특정 태그 접두어(예: [\"v\"])에만 적용. 빈 목록이면 모든 이미지(tagStatus=any)"
  type        = list(string)
  default     = []
}

variable "addon_ecr_pull_through_upstreams" {
  description = "pull-through cache 규칙 {prefix = upstream URL}. 빈 맵이면 생성 안 함. 익명 pull 가능한 업스트림만"
  type        = map(string)
  default     = {}
  # 예: { ecr-public = "public.ecr.aws", quay = "quay.io", registry-k8s-io = "registry.k8s.io" }
}
