# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_flowlog_vpc_id" {
  description = "Flow Log 을 붙일 기존 VPC ID. 직접 참조하려면 aws_vpc.<기존>.id 로 바꾼다"
  type        = string
}

variable "addon_flowlog_name" {
  description = "Flow Log·로그 그룹 Name 태그"
  type        = string
  default     = "vpc-flowlog"
}

variable "addon_flowlog_log_group_name" {
  description = "CloudWatch 로그 그룹 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "/vpc/flowlog"
}

variable "addon_flowlog_role_name" {
  description = "Flow Log 게시용 IAM Role 이름 (trust: vpc-flow-logs.amazonaws.com)"
  type        = string
  default     = "vpc-flowlog-role"
}

variable "addon_flowlog_traffic_type" {
  description = "수집 트래픽 유형: ALL / ACCEPT / REJECT"
  type        = string
  default     = "ALL"
}

variable "addon_flowlog_retention_days" {
  description = "로그 그룹 보존 기간 (일)"
  type        = number
  default     = 30
}

variable "addon_flowlog_kms_key_arn" {
  description = "로그 그룹 암호화 CMK ARN. 빈 문자열이면 AWS 관리 키"
  type        = string
  default     = ""
}

variable "addon_flowlog_aggregation_interval" {
  description = "집계 간격 (초). 60 또는 600 만 허용"
  type        = number
  default     = 600
}
