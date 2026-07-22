# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "region" {
  description = "NoSQL 모듈 리전"
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  description = "앱 EC2 용 VPC CIDR"
  type        = string
  default     = "10.71.0.0/16"
}

variable "public_subnet_cidr" {
  description = "앱 EC2 배치 퍼블릭 서브넷 CIDR"
  type        = string
  default     = "10.71.0.0/24"
}

# 과제지 Reservation Table & GSI 표와 정확히 일치 (이름 일치 채점 1-1, 1-2).
variable "reservation_table_name" {
  description = "예약 테이블 이름"
  type        = string
  default     = "bigbae-nosql-reservation-table"
}

variable "gsi_name" {
  description = "사용자별 예약 조회 GSI 이름"
  type        = string
  default     = "gsi-user-reservations"
}

variable "audit_table_name" {
  description = "감사 테이블 이름"
  type        = string
  default     = "bigbae-nosql-audit-table"
}

variable "lambda_name" {
  description = "Streams 후처리 Lambda 이름 (채점 1-3)"
  type        = string
  default     = "bigbae-nosql-reservation-audit"
}

variable "ec2_name" {
  description = "앱 EC2 Name 태그 (채점 1-4)"
  type        = string
  default     = "bigbae-nosql-app-ec2"
}

variable "instance_type" {
  description = "앱 EC2 인스턴스 타입 (유의사항 12)"
  type        = string
  default     = "t3.small"
}

variable "app_port" {
  description = "Flask 앱 바인딩 포트"
  type        = number
  default     = 8080
}
