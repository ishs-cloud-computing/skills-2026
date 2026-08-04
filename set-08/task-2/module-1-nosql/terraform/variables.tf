# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark2-1.sh)이 이름 정확 일치로 검사하는 값 전부 변수 (30% 변동 대비).
# 단, 지급 앱(docdb_client.py)이 region/secret name/db name/port 를 상수로
# 박아 두므로 region·secret_name 변경 시 지급 앱과 어긋난다 — NOTES 함정 절 참조.

variable "region" {
  description = "NoSQL 모듈 리전 (과제지 3)"
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_name" {
  description = "VPC Name 태그 (미채점 — 자유 지정, 유의사항 6)"
  type        = string
  default     = "skills-nosql-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.63.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Client EC2 배치 (Public IP 필요, 과제지 3-1)"
  type        = string
  default     = "10.63.0.0/24"
}

variable "db_subnets" {
  description = "DocumentDB subnet group 용 — 서로 다른 AZ 2개 필수"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "skills-nosql-sn-db-a" = { cidr = "10.63.10.0/24", az = "ap-northeast-2a" }
    "skills-nosql-sn-db-c" = { cidr = "10.63.11.0/24", az = "ap-northeast-2c" }
  }
}

variable "public_az" {
  type    = string
  default = "ap-northeast-2a"
}

variable "docdb_cluster_identifier" {
  description = "채점 1-1"
  type        = string
  default     = "skills-nosql-docdb-cluster"
}

variable "docdb_instance_identifier" {
  description = "채점 1-1"
  type        = string
  default     = "skills-nosql-docdb-instance-1"
}

variable "docdb_instance_class" {
  description = "과제지 3-2"
  type        = string
  default     = "db.t3.medium"
}

variable "docdb_port" {
  description = "지급 앱 상수와 일치 (과제지 3-1)"
  type        = number
  default     = 27017
}

variable "docdb_master_username" {
  type    = string
  default = "skillsadmin"
}

variable "backup_retention_days" {
  description = "과제지 3-2: 1일 이상"
  type        = number
  default     = 1
}

variable "kms_alias" {
  description = "채점 1-1 — alias/ 접두사 포함 전체 이름"
  type        = string
  default     = "alias/skills-nosql-docdb"
}

variable "secret_name" {
  description = "채점 1-2 (지급 앱 상수와 일치해야 함)"
  type        = string
  default     = "skills-nosql-docdb-secret"
}

variable "client_ec2_name" {
  description = "채점 1-2"
  type        = string
  default     = "skills-nosql-client-ec2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_port" {
  description = "지급 앱 Listen 포트 (과제지 3-1)"
  type        = number
  default     = 8080
}
