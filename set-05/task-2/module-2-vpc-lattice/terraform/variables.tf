# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "region" {
  description = "VPC Lattice 모듈 리전"
  type        = string
  default     = "ap-southeast-1"
}

variable "hub_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "spoke_vpc_cidr" {
  type    = string
  default = "192.168.0.0/16"
}

# 과제지 "VPC 구성" Hub/Spoke 표와 정확히 일치 (이름 일치 채점).
# az 는 가용영역 suffix(a/c)만 저장하고, full AZ 는 var.region 과 합성한다(vpc.tf).
# → 리전 변경 시 var.region 한 곳만 바꾸면 서브넷 AZ 가 함께 따라간다.
variable "subnets" {
  description = "Hub/Spoke 서브넷 정의 (az 는 가용영역 suffix)"
  type = map(object({
    cidr = string
    az   = string # 가용영역 suffix (예: a, c)
    vpc  = string # hub | spoke
    tier = string # public | private
  }))
  default = {
    "wsc-hub-sn-pub-a"    = { cidr = "10.0.0.0/24", az = "a", vpc = "hub", tier = "public" }
    "wsc-hub-sn-pub-c"    = { cidr = "10.0.1.0/24", az = "c", vpc = "hub", tier = "public" }
    "wsc-spoke-sn-pub-a"  = { cidr = "192.168.0.0/24", az = "a", vpc = "spoke", tier = "public" }
    "wsc-spoke-sn-pub-c"  = { cidr = "192.168.1.0/24", az = "c", vpc = "spoke", tier = "public" }
    "wsc-spoke-sn-priv-a" = { cidr = "192.168.2.0/24", az = "a", vpc = "spoke", tier = "private" }
    "wsc-spoke-sn-priv-c" = { cidr = "192.168.3.0/24", az = "c", vpc = "spoke", tier = "private" }
  }
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.small"
}

variable "app_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_password" {
  description = "Bastion SSH 패스워드 (과제 지정값)"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}
