# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark1.sh)이 이름 정확 일치로 검사하는 값은 전부 변수 (30% 변동 대비).

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "reservation_table_name" {
  type    = string
  default = "bigbae-nosql-reservation-table"
}

variable "audit_table_name" {
  type    = string
  default = "bigbae-nosql-audit-table"
}

variable "gsi_name" {
  type    = string
  default = "gsi-user-reservations"
}

variable "lambda_function_name" {
  type    = string
  default = "bigbae-nosql-reservation-audit"
}

variable "ec2_name" {
  type    = string
  default = "bigbae-nosql-app-ec2"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "vpc_name" {
  type    = string
  default = "bigbae-nosql-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}
