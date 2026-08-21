# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_rds_name_prefix" {
  description = "VPC·NAT·RTB 등 이름 접두. 과제지가 이름을 따로 지정한 리소스는 아래 개별 변수로 덮어쓴다"
  type        = string
  default     = "skills-rds"
}

# ----- VPC -----
variable "addon_rds_vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.60.0.0/16"
}

variable "addon_rds_public_subnet" {
  description = "퍼블릭 서브넷 1개 (NAT 전용)"
  type        = object({ cidr = string, az = string })
  default     = { cidr = "10.60.0.0/24", az = "ap-northeast-2a" }
}

variable "addon_rds_private_subnets" {
  description = "프라이빗 서브넷 (key = Name 태그). DB 서브넷 그룹·RDS Proxy 가 서로 다른 AZ 2개를 요구하므로 최소 2개"
  type        = map(object({ cidr = string, az = string }))
  default = {
    "skills-rds-private-a" = { cidr = "10.60.1.0/24", az = "ap-northeast-2a" }
    "skills-rds-private-b" = { cidr = "10.60.2.0/24", az = "ap-northeast-2c" }
  }
}

# ----- RDS -----
variable "addon_rds_identifier" {
  description = "DB 인스턴스 식별자. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "skills-rds-instance"
}

variable "addon_rds_engine_version" {
  description = "MySQL 엔진 버전. 과제지 명시 버전이 있으면 그 값 (메이저만 쓰면 최신 마이너 자동 선택)"
  type        = string
  default     = "8.0"
}

variable "addon_rds_parameter_group_family" {
  description = "파라미터 그룹 family. engine_version 메이저와 맞춘다"
  type        = string
  default     = "mysql8.0"
}

variable "addon_rds_parameters" {
  description = "커스텀 파라미터 (name => value). 과제지가 요구하는 값만 넣는다"
  type        = map(string)
  default     = {}
}

variable "addon_rds_instance_class" {
  description = "인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"
}

variable "addon_rds_allocated_storage" {
  description = "스토리지 GiB (gp3 최소 20)"
  type        = number
  default     = 20
}

variable "addon_rds_db_name" {
  description = "초기 데이터베이스 이름"
  type        = string
  default     = "skillsdb"
}

variable "addon_rds_username" {
  description = "마스터 사용자 이름"
  type        = string
  default     = "admin"
}

variable "addon_rds_port" {
  description = "DB 포트"
  type        = number
  default     = 3306
}

variable "addon_rds_multi_az" {
  description = "Multi-AZ 배포. 생성 시간 +10분 — 과제지가 요구할 때만 true"
  type        = bool
  default     = false
}

variable "addon_rds_backup_retention_days" {
  description = "자동 백업 보존 일수 (0 = 비활성). 과제지 명시값"
  type        = number
  default     = 7
}

variable "addon_rds_deletion_protection" {
  description = "삭제 보호. 채점 요구 시 true — teardown 전에 false 로 apply 해야 destroy 가 된다"
  type        = bool
  default     = false
}

variable "addon_rds_iam_auth" {
  description = "인스턴스 IAM DB 인증 활성화 (+ 클라이언트 Role 에 rds-db:connect). Proxy 쪽은 addon_rds_proxy_iam_auth"
  type        = bool
  default     = false
}

variable "addon_rds_secret_name" {
  description = "마스터 자격증명 Secrets Manager 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "skills-rds-credentials"
}

# ----- RDS Proxy -----
variable "addon_rds_proxy_enabled" {
  description = "RDS Proxy 생성 여부. 클라이언트 EC2 테스트 스크립트는 true 면 Proxy 엔드포인트, false 면 인스턴스 엔드포인트로 간다"
  type        = bool
  default     = true
}

variable "addon_rds_proxy_name" {
  description = "RDS Proxy 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "skills-rds-proxy"
}

variable "addon_rds_proxy_iam_auth" {
  description = "Proxy IAM 인증 REQUIRED. true 면 TLS 강제 — 클라이언트는 generate-db-auth-token + --ssl 로 붙는다"
  type        = bool
  default     = false
}

# ----- 클라이언트 EC2 -----
variable "addon_rds_client_ec2_name" {
  description = "클라이언트 EC2 Name 태그 (Role·Profile·SG 이름 파생)"
  type        = string
  default     = "skills-rds-client"
}

variable "addon_rds_client_instance_type" {
  description = "클라이언트 EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

# ----- RDS Event 구독 (선택) -----
variable "addon_rds_event_topic_name" {
  description = "RDS 이벤트 통지 SNS 토픽 이름. 빈 문자열이면 이벤트 구독을 만들지 않는다"
  type        = string
  default     = ""
}

variable "addon_rds_event_email" {
  description = "이벤트 통지 이메일. 빈 문자열이면 이메일 구독 생략"
  type        = string
  default     = ""
}

variable "addon_rds_event_categories" {
  description = "구독할 이벤트 카테고리 (source_type db-instance 기준)"
  type        = list(string)
  default     = ["availability", "failover", "failure", "maintenance"]
}
