# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "name_prefix" {
  description = "리소스 이름 공통 접두어 — 대회 당일 이름 변경 대비 (작업 규칙 5). k8s/eksctl 쪽 치환은 README 참고"
  type        = string
  default     = "wsc2026"
}

variable "region" {
  description = "모든 리소스를 생성할 리전 (유의사항 9)"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (요구사항 7)"
  type        = string
  default     = "wsc2026-eks-cluster"
}

variable "cluster_version" {
  description = "EKS 버전 (요구사항 7)"
  type        = string
  default     = "1.35"
}

variable "vpc_name" {
  description = "VPC 이름 (Reference01)"
  type        = string
  default     = "wsc2026-skills-vpc"
}

variable "vpc_cidr" {
  description = "VPC CIDR (Reference01)"
  type        = string
  default     = "192.168.0.0/16"
}

# Reference01: hub(public) / app(private) 2계층 × 2 AZ(a,b).
# hub 는 공용 RTB(wsc2026-skills-hub-rtb, IGW), app 은 AZ별 RTB + NAT.
variable "subnets" {
  description = "서브넷 정의 (Reference01)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "wsc2026-skills-hub-sub-a" = { cidr = "192.168.1.0/24", az = "ap-northeast-2a", tier = "public" }
    "wsc2026-skills-hub-sub-b" = { cidr = "192.168.10.0/24", az = "ap-northeast-2b", tier = "public" }
    "wsc2026-skills-app-sub-a" = { cidr = "192.168.2.0/24", az = "ap-northeast-2a", tier = "private" }
    "wsc2026-skills-app-sub-b" = { cidr = "192.168.20.0/24", az = "ap-northeast-2b", tier = "private" }
  }
}

variable "table_name" {
  description = "DynamoDB 테이블 이름 (요구사항 5)"
  type        = string
  default     = "wsc2026-book-table"
}

variable "ecr_name" {
  description = "ECR 리포지토리 이름 (요구사항 6)"
  type        = string
  default     = "wsc2026-book-ecr"
}

variable "lambda_function_name" {
  description = "Lambda 함수 이름 (요구사항 10)"
  type        = string
  default     = "wsc2026-book-get-function"
}

variable "player_number" {
  description = "선수 비번호 — S3 버킷 이름에 사용 (요구사항 9)"
  type        = string
  default     = "00"
}

variable "bucket_suffix" {
  description = "S3 버킷 이름의 임의 영문 4자리 (요구사항 9)"
  type        = string
  default     = "abcd"

  validation {
    condition     = can(regex("^[a-z]{4}$", var.bucket_suffix))
    error_message = "bucket_suffix 는 소문자 영문 4자리여야 합니다."
  }
}

# CloudFront/WAF 는 LBC 가 만드는 ALB(wsc2026-app-alb)에 의존하므로 2차 apply 로 미룬다.
# 1차: enable_cdn=false(기본) → VPC/KMS/DDB/ECR/S3/Lambda/IAM 생성
# 2차: 클러스터·ingress 생성 후 enable_cdn=true 로 재-apply → CloudFront/WAF/버킷정책 생성
variable "enable_cdn" {
  description = "CloudFront/WAF 등 ALB 의존 리소스 생성 여부 (2차 apply 에서 true)"
  type        = bool
  default     = false
}

# 작업용 bastion (bastion.tf). 채점 대상이 아니라 배포 작업 환경이므로
# 채점 전 apply -var="enable_bastion=false" 로 제거한다 (README step 9-3).
variable "enable_bastion" {
  description = "작업용 bastion 생성 여부 (채점 전 false 로 제거)"
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "작업용 bastion 인스턴스 타입"
  type        = string
  default     = "t3.small"
}