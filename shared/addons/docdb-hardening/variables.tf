# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ----- 클러스터 파라미터 그룹 -----
variable "addon_docdb_parameter_group_name" {
  description = "클러스터 파라미터 그룹 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "skills-docdb-params"
}

variable "addon_docdb_family" {
  description = "파라미터 그룹 family. 클러스터 engine_version 의 메이저와 맞춘다 (5.0.x → docdb5.0, 4.0.0 → docdb4.0). set-08 m1 은 engine_version 미지정 = 기본값(5.0)"
  type        = string
  default     = "docdb5.0"
}

variable "addon_docdb_tls" {
  description = "tls 파라미터. false 는 지급 앱(tls=True)의 접속을 깨뜨린다 — 과제지가 명시할 때만 끈다"
  type        = bool
  default     = true
}

variable "addon_docdb_audit_logs" {
  description = "audit_logs 파라미터. 클러스터 enabled_cloudwatch_logs_exports 에 audit 도 같이 넣어야 내보내진다"
  type        = bool
  default     = true
}

variable "addon_docdb_profiler" {
  description = "profiler 파라미터 (느린 쿼리 로그). enabled_cloudwatch_logs_exports 에 profiler 도 같이"
  type        = bool
  default     = false
}

variable "addon_docdb_profiler_threshold_ms" {
  description = "profiler 가 기록할 최소 실행 시간 (ms, 50~2147483646)"
  type        = number
  default     = 100
}

# ----- 읽기 인스턴스 -----
variable "addon_docdb_cluster_identifier" {
  description = "읽기 인스턴스를 붙일 기존 클러스터 식별자 (aws_docdb_cluster.<기존>.id). reader_count 0 이면 미사용"
  type        = string
  default     = ""
}

variable "addon_docdb_reader_count" {
  description = "추가할 읽기 인스턴스 개수. 0 이면 파라미터 그룹만 만든다"
  type        = number
  default     = 0
}

variable "addon_docdb_reader_identifier_prefix" {
  description = "읽기 인스턴스 식별자 접두어 — <prefix>-1, -2 ... 과제지 명시 이름에 맞춘다"
  type        = string
  default     = "skills-docdb-reader"
}

variable "addon_docdb_reader_instance_class" {
  description = "읽기 인스턴스 클래스. 기존 primary 와 같은 값이 무난"
  type        = string
  default     = "db.t3.medium"
}
