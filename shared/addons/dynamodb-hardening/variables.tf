# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ----- Streams → Lambda (dynamodb-stream.tf) -----
variable "addon_ddb_stream_arn" {
  description = "Streams 를 읽을 테이블의 stream_arn. 같은 루트 모듈이면 aws_dynamodb_table.<기존>.stream_arn 으로 바꾼다"
  type        = string
}

variable "addon_ddb_lambda_function_name" {
  description = "Streams 를 소비할 기존 Lambda 함수 이름 (aws_lambda_function.<기존>.function_name)"
  type        = string
}

variable "addon_ddb_lambda_role_name" {
  description = "그 Lambda 의 실행 Role 이름 — 스트림 읽기 정책을 여기에 붙인다 (aws_iam_role.<기존>.name)"
  type        = string
}

variable "addon_ddb_esm_batch_size" {
  description = "ESM 배치 크기 (Streams 최대 10000)"
  type        = number
  default     = 100
}

variable "addon_ddb_esm_max_retry_attempts" {
  description = "실패 배치 재시도 횟수 (-1 = 무제한, 기본값). 과제지가 '재시도 N회' 를 지정하면 그 값"
  type        = number
  default     = -1
}

variable "addon_ddb_esm_bisect_on_error" {
  description = "함수 오류 시 배치를 반으로 쪼개 재시도 (poison record 격리)"
  type        = bool
  default     = false
}

variable "addon_ddb_esm_on_failure_arn" {
  description = "실패 레코드 목적지 SQS/SNS ARN. 빈 문자열이면 destination_config 생략"
  type        = string
  default     = ""
}

# ----- Gateway 엔드포인트 (dynamodb-endpoint.tf) -----
variable "addon_ddb_vpc_id" {
  description = "엔드포인트를 붙일 VPC ID (aws_vpc.<기존>.id)"
  type        = string
}

variable "addon_ddb_route_table_ids" {
  description = "엔드포인트 경로를 넣을 라우트 테이블 ID 목록 (보통 private, aws_route_table.private[*].id)"
  type        = list(string)
}

variable "addon_ddb_endpoint_name" {
  description = "엔드포인트 Name 태그"
  type        = string
  default     = "dynamodb-endpoint"
}
