# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_cfh_log_bucket_prefix" {
  description = "CloudFront 표준 로그 버킷 이름 접두. 뒤에 -<account_id> 가 붙는다. 과제지 명시 이름이면 그대로"
  type        = string
  default     = "skills-cf-logs"
}

variable "addon_cfh_log_prefix" {
  description = "로그 객체 키 접두(logging_config.prefix). 끝에 / 포함"
  type        = string
  default     = "cloudfront/"
}
