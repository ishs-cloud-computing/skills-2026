# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark2-2.sh)이 이름·CIDR 정확 일치로 검사하는 값 전부 변수 (30% 변동 대비).

variable "region" {
  description = "VPC Lattice 모듈 리전 (과제지 4)"
  type        = string
  default     = "ap-northeast-1"
}

variable "client_vpc_name" {
  description = "Client VPC Name 태그 (채점 2-1)"
  type        = string
  default     = "skills-lattice-client-vpc"
}

variable "client_vpc_cidr" {
  type    = string
  default = "10.61.0.0/16"
}

variable "client_subnet_cidr" {
  type    = string
  default = "10.61.0.0/24"
}

variable "service_vpc_name" {
  description = "Service VPC Name 태그 (채점 2-1)"
  type        = string
  default     = "skills-lattice-service-vpc"
}

variable "service_vpc_cidr" {
  type    = string
  default = "10.62.0.0/16"
}

variable "service_subnet_cidr" {
  type    = string
  default = "10.62.0.0/24"
}

variable "az" {
  description = "단일 AZ 배치 (과제지 무요구 — 최소 구성)"
  type        = string
  default     = "ap-northeast-1a"
}

variable "client_ec2_name" {
  description = "Client EC2 Name 태그 (채점 2-2)"
  type        = string
  default     = "skills-lattice-client-ec2"
}

variable "service_ec2_name" {
  description = "Service EC2 Name 태그 (채점 2-2)"
  type        = string
  default     = "skills-lattice-service-ec2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "client_port" {
  description = "Client 앱 Listen 포트 (과제지 4-2)"
  type        = number
  default     = 80
}

variable "service_port" {
  description = "Service 앱 Listen 포트 (과제지 4-3)"
  type        = number
  default     = 8080
}

variable "sn_name" {
  description = "Service Network 이름 (채점 2-3)"
  type        = string
  default     = "skills-lattice-sn"
}

variable "lattice_service_name" {
  description = "Lattice Service 이름 (채점 2-3)"
  type        = string
  default     = "skills-lattice-order-service"
}

variable "tg_name" {
  description = "Target Group 이름 (채점 2-4)"
  type        = string
  default     = "skills-lattice-order-tg"
}

variable "listener_name" {
  description = "Listener 이름 (채점 2-4)"
  type        = string
  default     = "skills-lattice-http-listener"
}
