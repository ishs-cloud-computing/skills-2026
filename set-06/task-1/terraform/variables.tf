# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 대회 당일 30% 변경 대비 — 이름·CIDR·리전·타입은 전부 변수 (NOTES.md §4)

variable "region" {
  description = "전 리소스 리전 (WAF 만 us-east-1 예외)"
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  description = "전 리소스명 파생 prefix"
  type        = string
  default     = "gj2026"
}

variable "bibunho" {
  description = "선수 비번호 — S3 버킷명 suffix (gj2026-static-<비번호>)"
  type        = string
}

variable "vpc_cidr" {
  description = "gj2026-vpc CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "사용 AZ — 로그 스트림 이름과 단일 소스"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "private_subnet_cidrs" {
  description = "private 서브넷 CIDR (azs 와 인덱스 대응). Fluent Bit AZ 판별 정규식도 이 값에서 생성"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "cluster_service_cidr" {
  description = "EKS 서비스 CIDR (kube-dns ClusterIP 대역) — book pod SG 의 DNS egress 대상"
  type        = string
  default     = "172.20.0.0/16"
}

variable "cluster_version" {
  description = "EKS 버전"
  type        = string
  default     = "1.35"
}

variable "table_name" {
  description = "DynamoDB 테이블명 — k8s ConfigMap TABLE_NAME 과 단일 소스"
  type        = string
  default     = "books"
}

variable "gsi_name" {
  description = "DynamoDB GSI 이름 — Lambda 코드에도 주입"
  type        = string
  default     = "client_id-index"
}

variable "container_port" {
  description = "book 컨테이너 포트 — TG·SG·Service 공유"
  type        = number
  default     = 8080
}

variable "grafana_port" {
  description = "Grafana 컨테이너 포트"
  type        = number
  default     = 3000
}

variable "image_tag" {
  description = "book 이미지 태그 (채점 2-2 가 latest 지정)"
  type        = string
  default     = "latest"
}

variable "client_id_regex" {
  description = "WAF client_id 검증 정규식 (앵커 필수 — NOTES.md §3.10)"
  type        = string
  default     = "^[A-Za-z][A-Za-z0-9]*[0-9][A-Za-z0-9]*$"
}

variable "enable_ddb_write_deny" {
  description = "DynamoDB 쓰기 Deny 리소스 정책 활성화. 데이터 정리 시 일시 false (NOTES.md §3.4 함정)"
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Lambda 런타임 (채점 7-1)"
  type        = string
  default     = "python3.14"
}

variable "metric_namespace" {
  description = "Lambda EMF 커스텀 메트릭 네임스페이스"
  type        = string
  default     = "gj2026/reservation"
}

variable "log_group_name" {
  description = "book 액세스 로그 그룹 (채점 10-1)"
  type        = string
  default     = "/eks/book-svc/access"
}
