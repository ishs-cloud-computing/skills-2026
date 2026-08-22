# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_lamget_function_name" {
  description = "Lambda 함수 이름. 과제지 명시 이름과 정확히 일치시킨다. 역할·정책·로그 그룹 이름이 여기서 파생된다"
  type        = string
}

variable "addon_lamget_runtime" {
  description = "Lambda 런타임. 과제지 명시 버전으로"
  type        = string
  default     = "python3.13"
}

variable "addon_lamget_table_name" {
  description = "조회 대상 기존 DynamoDB 테이블 이름"
  type        = string
}

variable "addon_lamget_table_arn" {
  description = "조회 대상 기존 DynamoDB 테이블 ARN (최소권한 리소스 한정)"
  type        = string
}

variable "addon_lamget_key_name" {
  description = "쿼리스트링 필수 파라미터 = 테이블 PK(또는 GSI PK) 속성 이름. 없으면 400"
  type        = string
  default     = "booking_id"
}

variable "addon_lamget_index_name" {
  description = "GSI 이름. 비우면 테이블 PK GetItem, 채우면 GSI Query(최신 1건)"
  type        = string
  default     = ""
}

variable "addon_lamget_fields" {
  description = "200 응답 JSON 필드 순서. 채점지 예상 출력 순서와 동일하게"
  type        = list(string)
  default     = ["booking_id", "client_id", "username", "email", "concert_name", "created_at"]
}

variable "addon_lamget_table_kms_key_arn" {
  description = "테이블이 CMK(SSE-KMS)면 키 ARN — 역할에 Decrypt 부여. 빈 문자열이면 생략"
  type        = string
  default     = ""
}

variable "addon_lamget_log_retention_days" {
  description = "로그 그룹 보존 기간(일)"
  type        = number
  default     = 30
}

# ----- (a) ALB 노출 전용 -----
variable "addon_lamget_alb_listener_arn" {
  description = "규칙을 붙일 기존 ALB 리스너 ARN. 비우면 ALB 블록(alb-lambda.tf) 전체 생성 안 함"
  type        = string
  default     = ""
}

variable "addon_lamget_alb_rule_priority" {
  description = "리스너 규칙 priority. 기존 규칙(origin-verify·/health 등)과 겹치지 않게"
  type        = number
  default     = 30
}

variable "addon_lamget_alb_path" {
  description = "GET 으로 Lambda 에 보낼 경로 패턴"
  type        = string
  default     = "/v1/book"
}

variable "addon_lamget_alb_header_name" {
  description = "CloudFront origin-verify 커스텀 헤더 이름. 기존 규칙이 헤더를 검사하면 같은 값으로. 비우면 조건 생략"
  type        = string
  default     = ""
}

variable "addon_lamget_alb_header_value" {
  description = "origin-verify 헤더 값"
  type        = string
  default     = ""
  sensitive   = true
}
