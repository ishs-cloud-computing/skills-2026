# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_lattice_service_id" {
  description = "기존 VPC Lattice 서비스 ID(svc-...) 또는 ARN. 같은 state 면 aws_vpclattice_service.this.id 로 바꾼다"
  type        = string
}

variable "addon_lattice_service_name" {
  description = "기존 서비스 이름. 로그 그룹 이름 접두로 쓴다"
  type        = string
  default     = "wsc-app-service"
}

# ----- IAM auth policy (서비스 auth_type = AWS_IAM 와 함께) -----
variable "addon_lattice_auth_principal_arns" {
  description = "Invoke 를 허용할 IAM principal ARN 목록. 비어 있으면 같은 계정의 모든 인증된 principal 허용"
  type        = list(string)
  default     = []
}

# ----- 액세스 로그 -----
variable "addon_lattice_log_retention_days" {
  description = "액세스 로그 그룹 보존 일수"
  type        = number
  default     = 7
}

variable "addon_lattice_log_s3_bucket_arn" {
  description = "S3 로도 액세스 로그를 보내려면 버킷 ARN. 빈 문자열이면 CloudWatch Logs 만"
  type        = string
  default     = ""
}

# ----- 헤더 기반 리스너 룰 (version: v1/v2) -----
variable "addon_lattice_listener_id" {
  description = "기존 리스너 ID(listener-...). 같은 state 면 aws_vpclattice_listener.http.listener_id 로 바꾼다. 빈 문자열이면 룰을 만들지 않는다"
  type        = string
  default     = ""
}

variable "addon_lattice_header_name" {
  description = "라우팅 기준 헤더 이름"
  type        = string
  default     = "version"
}

variable "addon_lattice_v1_target_group_id" {
  description = "v1 대상 그룹 ID(tg-...). 같은 state 면 aws_vpclattice_target_group.v1.id"
  type        = string
  default     = ""
}

variable "addon_lattice_v2_target_group_id" {
  description = "v2 대상 그룹 ID(tg-...). 같은 state 면 aws_vpclattice_target_group.v2.id"
  type        = string
  default     = ""
}

variable "addon_lattice_rule_priority_base" {
  description = "헤더 룰 priority 시작값 (v1 = base, v2 = base+10). 기존 룰과 겹치지 않게"
  type        = number
  default     = 10
}
