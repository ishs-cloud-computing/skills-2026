# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

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

variable "name_prefix" {
  description = "네트워크 리소스(VPC·IGW·RTB·NAT) 이름 접두어. 채점 대상이 아니므로 한 곳에서 바꾼다."
  type        = string
  default     = "skm"
}

variable "vpc_cidr" {
  description = "skm VPC CIDR (과제지: VPC 자유 구성)"
  type        = string
  default     = "10.73.0.0/16"
}

# VPC 는 자유 구성이므로 이름은 채점 대상이 아니다. 구조만 2AZ pub/priv 로 통일.
variable "subnets" {
  description = "서브넷 정의"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "skm-subnet-pub-a"  = { cidr = "10.73.0.0/24", az = "ap-northeast-2a", tier = "public" }
    "skm-subnet-pub-c"  = { cidr = "10.73.1.0/24", az = "ap-northeast-2c", tier = "public" }
    "skm-subnet-priv-a" = { cidr = "10.73.10.0/24", az = "ap-northeast-2a", tier = "private" }
    "skm-subnet-priv-c" = { cidr = "10.73.11.0/24", az = "ap-northeast-2c", tier = "private" }
  }
}

variable "queue_name" {
  description = "주문 처리 SQS 이름 (채점 3-1)"
  type        = string
  default     = "skm-order-queue"
}

variable "ecr_repo_name" {
  description = "order-processor 이미지 ECR 리포지토리 이름 (채점 대상 아님)"
  type        = string
  default     = "skm-order-processor"
}
