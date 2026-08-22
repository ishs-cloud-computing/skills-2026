# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_firehose_name" {
  description = "Firehose 전송 스트림 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "wsc2026-orders-firehose"
}

variable "addon_firehose_stream_arn" {
  description = "소스 Kinesis Data Stream ARN (기존 리소스). 같은 state 면 aws_kinesis_stream.<기존>.arn 으로 바꾼다"
  type        = string
}

variable "addon_firehose_stream_kms_key_arn" {
  description = "소스 스트림이 CMK 로 암호화돼 있으면 그 키 ARN (역할에 kms:Decrypt 부여). AWS 관리 키(alias/aws/kinesis)·미암호화면 빈 문자열"
  type        = string
  default     = ""
}

variable "addon_firehose_bucket_name" {
  description = "적재 대상 S3 버킷 이름 (새로 만든다). 전역 유일 — 비번호 등 접미사 포함"
  type        = string
  default     = "wsc2026-orders-archive-000"
}

variable "addon_firehose_prefix" {
  description = "S3 객체 접두사. 과제지가 파티션 형식을 지정하면 그대로 넣는다"
  type        = string
  default     = "orders/!{timestamp:yyyy/MM/dd/HH}/"
}

variable "addon_firehose_error_prefix" {
  description = "변환·전송 실패 객체 접두사. !{firehose:error-output-type} 포함 필수"
  type        = string
  default     = "errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
}

variable "addon_firehose_buffer_mb" {
  description = "버퍼 크기(MiB) 1~128"
  type        = number
  default     = 5
}

variable "addon_firehose_buffer_sec" {
  description = "버퍼 간격(초) 0~900. 채점 중 빨리 보이려면 60"
  type        = number
  default     = 60
}

variable "addon_firehose_compression" {
  description = "S3 압축 형식: UNCOMPRESSED | GZIP | ZIP | Snappy | HADOOP_SNAPPY"
  type        = string
  default     = "UNCOMPRESSED"
}

variable "addon_firehose_role_name" {
  description = "Firehose 서비스 역할 이름"
  type        = string
  default     = "wsc2026-firehose-role"
}

variable "addon_firehose_log_retention_days" {
  description = "Firehose 오류 로그 그룹 보존 일수"
  type        = number
  default     = 7
}

# ----- Lambda ESM (Kinesis 트리거) — addon_firehose_esm_function_name 이 비어 있으면 만들지 않는다 -----
variable "addon_firehose_esm_function_name" {
  description = "스트림을 소비할 기존 Lambda 함수 이름. 빈 문자열이면 ESM·정책을 만들지 않는다"
  type        = string
  default     = ""
}

variable "addon_firehose_esm_lambda_role_name" {
  description = "위 Lambda 의 실행 역할 이름 (AWSLambdaKinesisExecutionRole 을 붙인다)"
  type        = string
  default     = ""
}

variable "addon_firehose_esm_batch_size" {
  description = "ESM 배치 크기"
  type        = number
  default     = 100
}

variable "addon_firehose_esm_starting_position" {
  description = "ESM 시작 위치: LATEST | TRIM_HORIZON"
  type        = string
  default     = "LATEST"
}
