variable "region" {
  description = "모든 리소스를 생성할 리전"
  type        = string
  default     = "ap-northeast-2"
}

# 비번호(<비번호>) — S3 버킷 이름 gj2026-static-<비번호> 에 사용 (요구사항 10)
variable "seat_number" {
  description = "선수 비번호. S3 버킷 gj2026-static-<비번호>"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
  default     = "gj2026-eks-cluster"
}

variable "cluster_version" {
  description = "EKS 버전"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "gj2026-vpc CIDR (Reference01)"
  type        = string
  default     = "10.0.0.0/16"
}

# Reference01 의 서브넷/라우트테이블 정의를 그대로 사용한다.
# set-06 은 인터넷 통신이 불가능한 Private subnet 2개만 존재한다 (요구사항 3).
variable "subnets" {
  description = "서브넷 정의 (Reference01)"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "gj2026-private-subnet-a" = { cidr = "10.0.10.0/24", az = "ap-northeast-2a" }
    "gj2026-private-subnet-b" = { cidr = "10.0.11.0/24", az = "ap-northeast-2b" }
  }
}

variable "addon_instance_type" {
  description = "Addon NodeGroup 인스턴스 타입 (요구사항 7)"
  type        = string
  default     = "t3.medium"
}

variable "app_instance_type" {
  description = "App NodeGroup 인스턴스 타입 (요구사항 7)"
  type        = string
  default     = "m5.large"
}

variable "node_desired_count" {
  description = "각 NodeGroup 의 노드 수 (요구사항 7)"
  type        = number
  default     = 2
}

variable "lambda_runtime" {
  description = "Lambda 런타임 (요구사항 11)"
  type        = string
  default     = "python3.14"
}

variable "grafana_admin_password" {
  description = "Grafana 관리자 비밀번호 (요구사항 14)"
  type        = string
  default     = "Skills53#"
  sensitive   = true
}
