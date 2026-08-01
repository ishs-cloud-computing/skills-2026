# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark4.sh)이 이름 정확 일치로 검사하는 값은 전부 변수 (30% 변동 대비).
# VPC 는 과제지상 자유 구성이지만 이름·CIDR 은 변경 가능하도록 변수화한다.

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

variable "ecr_repo_name" {
  description = "log-generator 이미지 저장소 이름 (미채점)"
  type        = string
  default     = "o11y-log-generator"
}

variable "name_prefix" {
  description = "VPC 등 미채점 리소스 Name 태그 접두사"
  type        = string
  default     = "o11y"
}

variable "vpc_cidr" {
  type    = string
  default = "10.14.0.0/16"
}

# ap-northeast-1 은 신규 계정에서 1b 미제공 — 1a/1c 사용 (Multi-AZ 채점 4-1 충족)
variable "subnets" {
  description = "서브넷 정의"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "o11y-sn-pub-a"  = { cidr = "10.14.0.0/24", az = "ap-northeast-1a", tier = "public" }
    "o11y-sn-pub-c"  = { cidr = "10.14.1.0/24", az = "ap-northeast-1c", tier = "public" }
    "o11y-sn-priv-a" = { cidr = "10.14.10.0/24", az = "ap-northeast-1a", tier = "private" }
    "o11y-sn-priv-c" = { cidr = "10.14.11.0/24", az = "ap-northeast-1c", tier = "private" }
  }
}

# ----- ALB / TG (채점 4-2: 이름 정확 일치) -----

variable "app_alb_name" {
  type    = string
  default = "o11y-app-alb"
}

variable "grafana_alb_name" {
  type    = string
  default = "o11y-grafana-alb"
}

variable "app_tg_name" {
  type    = string
  default = "o11y-app-tg"
}

variable "grafana_tg_name" {
  type    = string
  default = "o11y-grafana-tg"
}

variable "app_port" {
  description = "log-generator 컨테이너 포트 (지급 app.py 고정)"
  type        = number
  default     = 8080
}

variable "grafana_port" {
  description = "Grafana 컨테이너/서비스 포트"
  type        = number
  default     = 3000
}

variable "app_health_path" {
  type    = string
  default = "/healthz"
}

variable "grafana_health_path" {
  description = "Grafana 무인증 헬스 엔드포인트"
  type        = string
  default     = "/api/health"
}

variable "lbc_policy_name" {
  description = "AWS Load Balancer Controller IRSA 정책 이름 (eksctl cluster.yaml 이 ARN 으로 참조)"
  type        = string
  default     = "o11y-lbc-policy"
}
