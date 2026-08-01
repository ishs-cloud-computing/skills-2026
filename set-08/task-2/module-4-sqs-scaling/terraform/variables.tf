# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark2-4.sh)이 이름 정확 일치로 검사하는 값 전부 변수 (30% 변동 대비).

variable "region" {
  description = "SQS Scaling 모듈 리전 (과제지 6)"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (채점 4-1)"
  type        = string
  default     = "skills-sqs-cluster"
}

variable "queue_name" {
  description = "SQS 큐 이름 (채점 4-2)"
  type        = string
  default     = "skills-sqs-queue"
}

variable "visibility_timeout" {
  description = "과제지 6-3: 30초 이상"
  type        = number
  default     = 30
}

variable "ecr_repo_name" {
  description = "worker 이미지 저장소 (미채점 — 이미지 출처 자유)"
  type        = string
  default     = "skills-sqs-worker"
}

variable "name_prefix" {
  description = "미채점 리소스 Name 태그 접두사"
  type        = string
  default     = "skills-sqs"
}

variable "vpc_cidr" {
  type    = string
  default = "10.64.0.0/16"
}

variable "subnets" {
  description = "서브넷 정의 (Fargate/Karpenter 노드는 private)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "skills-sqs-sn-pub-a"  = { cidr = "10.64.0.0/24", az = "us-west-2a", tier = "public" }
    "skills-sqs-sn-pub-b"  = { cidr = "10.64.1.0/24", az = "us-west-2b", tier = "public" }
    "skills-sqs-sn-priv-a" = { cidr = "10.64.10.0/24", az = "us-west-2a", tier = "private" }
    "skills-sqs-sn-priv-b" = { cidr = "10.64.11.0/24", az = "us-west-2b", tier = "private" }
  }
}
