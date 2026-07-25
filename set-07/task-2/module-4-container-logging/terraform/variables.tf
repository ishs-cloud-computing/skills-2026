# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "region" {
  description = "Container Logging 모듈 리전"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (채점 4-1)"
  type        = string
  default     = "o11y-cluster"
}

variable "name_prefix" {
  description = "네트워크·SG 이름 접두어. 채점 대상이 아니므로 한 곳에서 바꾼다."
  type        = string
  default     = "o11y"
}

variable "vpc_cidr" {
  description = "o11y VPC CIDR"
  type        = string
  default     = "10.74.0.0/16"
}

variable "subnets" {
  description = "서브넷 정의 (Multi-AZ 노드 배치용 2AZ)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "o11y-subnet-pub-a"  = { cidr = "10.74.0.0/24", az = "ap-northeast-1a", tier = "public" }
    "o11y-subnet-pub-c"  = { cidr = "10.74.1.0/24", az = "ap-northeast-1c", tier = "public" }
    "o11y-subnet-priv-a" = { cidr = "10.74.10.0/24", az = "ap-northeast-1a", tier = "private" }
    "o11y-subnet-priv-c" = { cidr = "10.74.11.0/24", az = "ap-northeast-1c", tier = "private" }
  }
}

# 과제지 표와 정확히 일치 (채점 4-2 가 이름으로 ALB/TG 를 조회한다).
variable "app_alb_name" {
  description = "앱 ALB 이름"
  type        = string
  default     = "o11y-app-alb"
}

variable "app_tg_name" {
  description = "앱 Target Group 이름"
  type        = string
  default     = "o11y-app-tg"
}

variable "grafana_alb_name" {
  description = "Grafana ALB 이름"
  type        = string
  default     = "o11y-grafana-alb"
}

variable "grafana_tg_name" {
  description = "Grafana Target Group 이름"
  type        = string
  default     = "o11y-grafana-tg"
}

variable "ecr_repo_name" {
  description = "log-generator 이미지 ECR 리포지토리 이름 (채점 대상 아님)"
  type        = string
  default     = "o11y-log-generator"
}
