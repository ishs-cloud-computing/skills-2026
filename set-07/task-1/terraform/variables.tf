# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "region" {
  description = "모든 리소스를 생성할 리전 (유의사항 7)"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (요구사항 8)"
  type        = string
  default     = "unicorn-eks-cluster"
}

variable "cluster_version" {
  description = "EKS 버전 (요구사항 8)"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "unicorn-vpc CIDR (요구사항 3)"
  type        = string
  default     = "10.97.0.0/16"
}

# 요구사항 3: public/private 2계층 × 3 AZ(a,b,c), 24bit, Zero Subnet 허용.
# CIDR 은 VPC 기준 public=0,1,2 / private=10,11,12 번째.
variable "subnets" {
  description = "서브넷 정의 (요구사항 3)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "unicorn-subnet-pub-a"  = { cidr = "10.97.0.0/24", az = "ap-northeast-2a", tier = "public" }
    "unicorn-subnet-pub-b"  = { cidr = "10.97.1.0/24", az = "ap-northeast-2b", tier = "public" }
    "unicorn-subnet-pub-c"  = { cidr = "10.97.2.0/24", az = "ap-northeast-2c", tier = "public" }
    "unicorn-subnet-priv-a" = { cidr = "10.97.10.0/24", az = "ap-northeast-2a", tier = "private" }
    "unicorn-subnet-priv-b" = { cidr = "10.97.11.0/24", az = "ap-northeast-2b", tier = "private" }
    "unicorn-subnet-priv-c" = { cidr = "10.97.12.0/24", az = "ap-northeast-2c", tier = "private" }
  }
}

variable "node_instance_type" {
  description = "EKS 노드 인스턴스 타입 (유의사항 12)"
  type        = string
  default     = "t3.medium"
}

# 요구사항 9 / 11 / 12: 선수 등번호. ExternalId(unicorn-audit-2026<번호>),
# Grafana 계정(skills<번호> / HelloKrSkills!<번호>@) 에 사용.
variable "player_number" {
  description = "선수 등번호"
  type        = string
  default     = "00"
}

variable "audit_external_id_prefix" {
  description = "Audit Role External ID prefix (요구사항 11)"
  type        = string
  default     = "unicorn-audit-2026"
}

variable "grafana_admin_user" {
  description = "Grafana 관리자 ID (요구사항 12). 기본 skills<등번호>"
  type        = string
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana 관리자 PW (요구사항 12). 기본 HelloKrSkills!<등번호>@"
  type        = string
  default     = ""
  sensitive   = true
}

# 채점 시 XSS 공격이 들어온다(2026-07-31 정정 3). 당일 벡터가 바뀌어도 목록만 늘리면 된다.
variable "waf_xss_rules" {
  description = "Custom Response 를 적용할 AWSManagedRulesCommonRuleSet 내 XSS 룰 (요구사항 10-3)"
  type        = list(string)
  default = [
    "CrossSiteScripting_QUERYARGUMENTS",
    "CrossSiteScripting_URIPATH",
    "CrossSiteScripting_BODY",
    "CrossSiteScripting_COOKIE",
  ]
}
