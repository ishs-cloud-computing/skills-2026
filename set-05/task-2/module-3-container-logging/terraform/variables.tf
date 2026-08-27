# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "region" {
  description = "Container Logging 모듈 리전"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  type    = string
  default = "wsc-logging-cluster"
}

variable "vpc_cidr" {
  type    = string
  default = "10.3.0.0/16"
}

# 과제지 "VPC 구성" 표와 정확히 일치 (이름 일치 채점).
variable "subnets" {
  description = "서브넷 정의"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "wsc-logging-sn-pub-a"  = { cidr = "10.3.0.0/24", az = "ap-northeast-1a", tier = "public" }
    "wsc-logging-sn-pub-c"  = { cidr = "10.3.1.0/24", az = "ap-northeast-1c", tier = "public" }
    "wsc-logging-sn-priv-a" = { cidr = "10.3.2.0/24", az = "ap-northeast-1a", tier = "private" }
    "wsc-logging-sn-priv-c" = { cidr = "10.3.3.0/24", az = "ap-northeast-1c", tier = "private" }
  }
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
}
