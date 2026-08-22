# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_sfnhard_state_machine_name" {
  description = "기존 state machine 이름. 로그 그룹·규칙 이름의 접두이자 EventBridge 대상 ARN 조립에 쓴다"
  type        = string
}

variable "addon_sfnhard_role_name" {
  description = "기존 state machine 실행 역할 이름. 로그 전달·X-Ray·SNS Publish 정책이 여기 붙는다"
  type        = string
}

variable "addon_sfnhard_log_retention_days" {
  description = "로그 그룹 보존 기간(일)"
  type        = number
  default     = 7
}

variable "addon_sfnhard_sns_topic_arn" {
  description = "SNS Publish Task 대상 토픽 ARN. 비우면 sns:Publish 문장 생략"
  type        = string
  default     = ""
}

variable "addon_sfnhard_s3_bucket_name" {
  description = "Object Created 로 state machine 을 시작할 기존 버킷 이름. 비우면 EventBridge 규칙 생성 안 함"
  type        = string
  default     = ""
}

variable "addon_sfnhard_s3_key_prefix" {
  description = "트리거 대상 키 접두 (예: input/). 빈 문자열이면 전체"
  type        = string
  default     = "input/"
}
