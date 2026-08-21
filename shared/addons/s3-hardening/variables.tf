# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_s3h_bucket_name" {
  description = "보강 대상 기존 버킷 이름. 직접 참조하려면 aws_s3_bucket.<기존>.id 로 바꾼다"
  type        = string
  default     = "skills-static-bucket"
}

variable "addon_s3h_lifecycle_rules" {
  description = "수명주기 규칙 map. key=규칙 id. prefix 빈 문자열=전체, 0=해당 동작 없음"
  type = map(object({
    prefix                   = optional(string, "")
    transition_days          = optional(number, 0)
    transition_storage_class = optional(string, "STANDARD_IA")
    expiration_days          = optional(number, 0)
    noncurrent_days          = optional(number, 0)
  }))
  default = {
    logs = { prefix = "logs/", transition_days = 30, expiration_days = 90, noncurrent_days = 30 }
  }
}

variable "addon_s3h_log_bucket_prefix" {
  description = "서버 액세스 로그 대상 버킷 이름 접두. 뒤에 -<account_id> 가 붙는다"
  type        = string
  default     = "skills-s3-access-logs"
}

variable "addon_s3h_log_prefix" {
  description = "서버 액세스 로그 객체 키 접두(target_prefix). 끝에 / 포함"
  type        = string
  default     = "s3/"
}
