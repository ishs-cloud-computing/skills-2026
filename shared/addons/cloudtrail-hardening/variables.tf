# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_trail_name" {
  description = "Trail 이름. 채점 스크립트가 describe-trails 로 직접 읽으므로 과제지와 정확히 일치시킨다"
  type        = string
}

variable "addon_trail_bucket_prefix" {
  description = "로그 버킷 이름 접두 (<prefix>-<account_id>, 전역 유일)"
  type        = string
  default     = "cloudtrail-logs"
}

variable "addon_trail_s3_key_prefix" {
  description = "버킷 안 key prefix (예: cloudtrail). 빈 문자열이면 AWSLogs/ 루트. 버킷 정책 경로는 자동으로 맞춰진다"
  type        = string
  default     = ""
}

variable "addon_trail_multi_region" {
  description = "멀티리전 Trail 여부 (과제지 '모든 리전' 요구 시 true)"
  type        = bool
  default     = false
}

variable "addon_trail_include_global_events" {
  description = "IAM·STS·CloudFront 등 글로벌 서비스 이벤트 포함 여부. EventBridge 의 IAM/ConsoleLogin 룰을 쓰면 true"
  type        = bool
  default     = true
}

variable "addon_trail_read_write_type" {
  description = "management 이벤트 선택: All / ReadOnly / WriteOnly"
  type        = string
  default     = "All"
}

variable "addon_trail_cw_logs_enabled" {
  description = "CloudWatch Logs 로그 그룹 연동 여부 (메트릭 필터·알람 문항이 같이 나올 때 true)"
  type        = bool
  default     = false
}

variable "addon_trail_log_group_name" {
  description = "CloudWatch Logs 로그 그룹 이름 (cw_logs_enabled 일 때)"
  type        = string
  default     = "/aws/cloudtrail/trail"
}

variable "addon_trail_log_retention_days" {
  description = "로그 그룹 보존 기간 (일)"
  type        = number
  default     = 30
}

variable "addon_trail_kms_enabled" {
  description = "Trail 로그(및 로그 그룹) SSE-KMS CMK 생성·적용 여부"
  type        = bool
  default     = false
}

variable "addon_trail_kms_alias" {
  description = "CMK alias (alias/ 접두 제외)"
  type        = string
  default     = "cloudtrail-logs"
}
