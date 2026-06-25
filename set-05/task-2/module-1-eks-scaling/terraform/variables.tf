variable "region" {
  description = "EKS Scaling 모듈 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
  default     = "wsc-scaling-cluster"
}

variable "vpc_cidr" {
  description = "wsc-scaling-vpc CIDR"
  type        = string
  default     = "10.11.0.0/16"
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
    "wsc-scaling-sn-pub-a"  = { cidr = "10.11.0.0/24", az = "ap-northeast-2a", tier = "public" }
    "wsc-scaling-sn-pub-c"  = { cidr = "10.11.1.0/24", az = "ap-northeast-2c", tier = "public" }
    "wsc-scaling-sn-priv-a" = { cidr = "10.11.10.0/24", az = "ap-northeast-2a", tier = "private" }
    "wsc-scaling-sn-priv-c" = { cidr = "10.11.11.0/24", az = "ap-northeast-2c", tier = "private" }
  }
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "sqs_name" {
  description = "KEDA 스케일링 트리거용 SQS 이름"
  type        = string
  default     = "wsc-scaling-sqs"
}

variable "ssh_password" {
  description = "Bastion / Node SSH 패스워드 (과제 지정값)"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}
