# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_waf_name" {
  description = "Web ACL 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
}

variable "addon_waf_rate_limit" {
  description = "rate-based rule 임계 요청 수 (evaluation window 당, IP 기준)"
  type        = number
  default     = 100
}

variable "addon_waf_rate_window_sec" {
  description = "rate-based rule 평가 윈도 (초). 60/120/300/600 만 허용"
  type        = number
  default     = 60
}

# REGIONAL 전용 — CLOUDFRONT 스니펫을 쓰면 이 변수는 tfvars 에서 생략한다.
variable "addon_waf_target_arn" {
  description = "Web ACL 을 연결할 ALB/API Gateway ARN (REGIONAL 전용)"
  type        = string
  default     = ""
}
