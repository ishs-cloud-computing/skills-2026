# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_msk_cluster_name" {
  description = "기존 MSK 클러스터 이름. 로그 그룹·configuration 이름 접두로 쓴다"
  type        = string
  default     = "wsc2026-msk-cluster"
}

# ----- 브로커 로그 (CloudWatch Logs) -----
variable "addon_msk_log_group_name" {
  description = "브로커 로그 그룹 이름. 과제지 명시값이 있으면 정확히 일치시킨다"
  type        = string
  default     = "/aws/msk/wsc2026-msk-cluster"
}

variable "addon_msk_log_retention_days" {
  description = "브로커 로그 보존 일수"
  type        = number
  default     = 7
}

# ----- 클러스터 configuration (server.properties) -----
variable "addon_msk_configuration_name" {
  description = "MSK configuration 이름. 과제지 명시값이 있으면 정확히 일치시킨다"
  type        = string
  default     = "wsc2026-msk-config"
}

variable "addon_msk_kafka_versions" {
  description = "configuration 이 적용 가능한 Kafka 버전 목록. 기존 클러스터 kafka_version 을 반드시 포함"
  type        = list(string)
  default     = ["3.6.0"]
}

variable "addon_msk_server_properties" {
  description = "server.properties 본문. 과제지가 요구한 키만 넣는다 (auto.create.topics.enable 등)"
  type        = string
  default     = <<-EOT
    auto.create.topics.enable=false
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=3
    log.retention.hours=168
  EOT
}

# ----- Lambda ESM (MSK 트리거) — addon_msk_esm_function_name 이 비어 있으면 만들지 않는다 -----
variable "addon_msk_cluster_arn" {
  description = "ESM 을 붙일 기존 MSK 클러스터 ARN. 같은 state 면 aws_msk_cluster.<기존>.arn 으로 바꾼다"
  type        = string
  default     = ""
}

variable "addon_msk_esm_function_name" {
  description = "MSK 토픽을 소비할 기존 Lambda 함수 이름. 빈 문자열이면 ESM·정책을 만들지 않는다"
  type        = string
  default     = ""
}

variable "addon_msk_esm_lambda_role_name" {
  description = "위 Lambda 의 실행 역할 이름 (ESM 폴러 정책·kafka-cluster 데이터 액션을 붙인다)"
  type        = string
  default     = ""
}

variable "addon_msk_esm_topics" {
  description = "ESM 이 소비할 토픽 이름 목록"
  type        = list(string)
  default     = ["wsc2026-sensor-raw"]
}

variable "addon_msk_esm_batch_size" {
  description = "ESM 배치 크기"
  type        = number
  default     = 100
}
