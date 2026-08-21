# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_albh_log_bucket_prefix" {
  description = "ALB 액세스 로그 버킷 이름 접두. 뒤에 -<account_id> 가 붙는다. 과제지 명시 이름이면 그대로"
  type        = string
  default     = "skills-alb-logs"
}

variable "addon_albh_log_prefix" {
  description = "access_logs.prefix 값. 빈 문자열이면 버킷 루트(AWSLogs/...)"
  type        = string
  default     = "alb"
}

variable "addon_albh_listener_arn" {
  description = "헤더 조건 규칙을 붙일 기존 HTTP 리스너 ARN. 빈 문자열이면 규칙 생성 안 함. 직접 참조하려면 aws_lb_listener.<기존>.arn"
  type        = string
  default     = ""
}

variable "addon_albh_target_group_arn" {
  description = "헤더 조건 규칙·HTTPS 리스너가 forward 할 타깃 그룹 ARN. 직접 참조하려면 aws_lb_target_group.<기존>.arn"
  type        = string
  default     = ""
}

variable "addon_albh_rule_priority" {
  description = "헤더 조건 규칙 priority. 기존 규칙과 겹치지 않게"
  type        = number
  default     = 1
}

variable "addon_albh_header_name" {
  description = "오리진 검증 헤더 이름. CloudFront origin custom_header.name 과 동일"
  type        = string
  default     = "X-Origin-Verify"
}

variable "addon_albh_header_value" {
  description = "오리진 검증 헤더 값. CloudFront origin custom_header.value 와 동일(20자 이상 요구 세트 있음)"
  type        = string
  default     = ""
}

variable "addon_albh_alb_arn" {
  description = "HTTPS 리스너를 붙일 기존 ALB ARN. 직접 참조하려면 aws_lb.<기존>.arn"
  type        = string
  default     = ""
}

variable "addon_albh_certificate_arn" {
  description = "HTTPS 리스너용 ACM 인증서 ARN(ALB 와 같은 리전). 빈 문자열이면 HTTPS 리스너 생성 안 함"
  type        = string
  default     = ""
}
