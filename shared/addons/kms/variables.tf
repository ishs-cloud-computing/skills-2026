# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_kms_alias" {
  description = "KMS alias 이름 (alias/ 접두어 제외). 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
}

variable "addon_kms_description" {
  description = "키 설명 (콘솔·채점 스크립트 표시용)"
  type        = string
  default     = "task-1 addon CMK"
}

variable "addon_kms_rotation_days" {
  description = "자동 회전 주기 (일). 과제지가 지정하면 그 값으로 (set-07 은 90 이었다)"
  type        = number
  default     = 365
}
