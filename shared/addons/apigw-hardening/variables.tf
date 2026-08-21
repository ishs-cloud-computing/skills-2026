# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_apigwhard_api_name" {
  description = "기존 REST API 이름. 로그 그룹·역할 이름의 접두가 된다"
  type        = string
}

variable "addon_apigwhard_rest_api_id" {
  description = "기존 aws_api_gateway_rest_api ID"
  type        = string
}

variable "addon_apigwhard_stage_name" {
  description = "기존 스테이지 이름 (method settings 대상)"
  type        = string
  default     = "prod"
}

variable "addon_apigwhard_log_retention_days" {
  description = "액세스 로그 그룹 보존 기간(일)"
  type        = number
  default     = 7
}

variable "addon_apigwhard_throttle_burst" {
  description = "스테이지 메서드 throttling burst"
  type        = number
  default     = 100
}

variable "addon_apigwhard_throttle_rate" {
  description = "스테이지 메서드 throttling rate (req/s)"
  type        = number
  default     = 50
}

variable "addon_apigwhard_logging_level" {
  description = "실행 로그 수준 OFF/ERROR/INFO. OFF 가 아니면 aws_api_gateway_account 역할 필수"
  type        = string
  default     = "INFO"
}

variable "addon_apigwhard_cors_resource_id" {
  description = "CORS OPTIONS 메서드를 붙일 기존 aws_api_gateway_resource ID. 비우면 CORS 리소스 생성 안 함"
  type        = string
  default     = ""
}

variable "addon_apigwhard_cors_origin" {
  description = "Access-Control-Allow-Origin 값"
  type        = string
  default     = "*"
}
