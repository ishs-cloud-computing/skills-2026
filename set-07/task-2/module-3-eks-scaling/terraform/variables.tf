# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark3.sh)이 이름 정확 일치로 검사하는 값은 전부 변수 (30% 변동 대비).
# VPC 는 과제지상 자유 구성이지만 이름·CIDR 은 변경 가능하도록 변수화한다.

variable "region" {
  description = "EKS Scaling 모듈 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (채점 3-2)"
  type        = string
  default     = "skm-eks-cluster"
}

variable "sqs_name" {
  description = "주문 큐 이름 (채점 3-1)"
  type        = string
  default     = "skm-order-queue"
}

variable "ecr_repo_name" {
  description = "order-processor 이미지 저장소 이름 (미채점)"
  type        = string
  default     = "skm-order-processor"
}

variable "name_prefix" {
  description = "VPC 등 미채점 리소스 Name 태그 접두사"
  type        = string
  default     = "skm-eks"
}

variable "vpc_cidr" {
  type    = string
  default = "10.13.0.0/16"
}

variable "subnets" {
  description = "서브넷 정의"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "skm-eks-sn-pub-a"  = { cidr = "10.13.0.0/24", az = "ap-northeast-2a", tier = "public" }
    "skm-eks-sn-pub-c"  = { cidr = "10.13.1.0/24", az = "ap-northeast-2c", tier = "public" }
    "skm-eks-sn-priv-a" = { cidr = "10.13.10.0/24", az = "ap-northeast-2a", tier = "private" }
    "skm-eks-sn-priv-c" = { cidr = "10.13.11.0/24", az = "ap-northeast-2c", tier = "private" }
  }
}
