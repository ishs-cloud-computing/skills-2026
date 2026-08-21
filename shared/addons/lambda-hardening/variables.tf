# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_lamhard_function_name" {
  description = "강화 대상 기존 Lambda 함수 이름. 로그 그룹 이름(/aws/lambda/<이름>)·DLQ 정책 이름의 접두가 된다"
  type        = string
}

variable "addon_lamhard_role_name" {
  description = "기존 Lambda 실행 역할 이름. 관리형 정책(VPC·X-Ray)과 DLQ SendMessage 정책이 여기에 붙는다"
  type        = string
}

variable "addon_lamhard_log_retention_days" {
  description = "선생성 로그 그룹 보존 기간(일). 과제지 명시값으로"
  type        = number
  default     = 30
}

variable "addon_lamhard_log_kms_key_arn" {
  description = "로그 그룹 암호화 CMK ARN. 빈 문자열이면 미암호화. key policy 에 logs 서비스 문장 필수(kms 키트 참고)"
  type        = string
  default     = ""
}

variable "addon_lamhard_dlq_name" {
  description = "DLQ(SQS) 이름. 빈 문자열이면 생성 안 함. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = ""
}

variable "addon_lamhard_enable_vpc_policy" {
  description = "vpc_config 를 붙일 때 true — AWSLambdaVPCAccessExecutionRole 부착"
  type        = bool
  default     = false
}

variable "addon_lamhard_enable_xray_policy" {
  description = "tracing_config Active 를 붙일 때 true — AWSXRayDaemonWriteAccess 부착"
  type        = bool
  default     = false
}
