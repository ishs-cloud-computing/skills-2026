# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_secret_name" {
  description = "시크릿 이름. 과제지 명시 이름(지급 앱이 상수로 읽는 이름)과 정확히 일치시킨다"
  type        = string
}

variable "addon_secret_values" {
  description = "시크릿 JSON 키/값 맵. 예: { username = \"admin\", password = \"...\", host = \"...\" }"
  type        = map(string)
  sensitive   = true
}

variable "addon_secret_kms_key_arn" {
  description = "암호화 CMK ARN (kms 키트 aws_kms_key.addon.arn). 빈 문자열이면 AWS 관리 키 aws/secretsmanager"
  type        = string
  default     = ""
}

variable "addon_secret_recovery_window_days" {
  description = "삭제 유예 일수. 0 = 즉시 삭제(재생성 가능), 7~30 = 유예"
  type        = number
  default     = 0
}

variable "addon_secret_read_policy_name" {
  description = "읽기 IAM 정책 이름"
  type        = string
  default     = "skills-secret-read"
}

variable "addon_secret_reader_role_names" {
  description = "읽기 정책을 붙일 기존 IAM Role 이름 목록 (aws_iam_role.<기존>.name). 빈 목록이면 정책만 만든다"
  type        = list(string)
  default     = []
}

# ----- 회전 (선택) -----
variable "addon_secret_rotation_lambda_arn" {
  description = "회전 Lambda 함수 ARN. 빈 문자열이면 회전 리소스를 만들지 않는다"
  type        = string
  default     = ""
}

variable "addon_secret_rotation_days" {
  description = "자동 회전 주기 (일)"
  type        = number
  default     = 30
}

variable "addon_secret_rotate_immediately" {
  description = "회전 설정 시 즉시 1회 회전. Lambda 가 검증되지 않았으면 false"
  type        = bool
  default     = false
}
