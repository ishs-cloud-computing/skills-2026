# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ----- Network -----

variable "addon_kc_vpc_name" {
  description = "VPC 이름 태그. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "keycloak-vpc"
}

variable "addon_kc_vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.30.0.0/16"
}

variable "addon_kc_public_subnets" {
  description = "퍼블릭 서브넷 (key = Name 태그). ALB 가 2 AZ 를 요구하므로 최소 2개"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "keycloak-pub-a" = { cidr = "10.30.0.0/24", az = "ap-northeast-2a" }
    "keycloak-pub-b" = { cidr = "10.30.1.0/24", az = "ap-northeast-2b" }
  }
}

# ----- EC2 / Keycloak -----

variable "addon_kc_instance_name" {
  description = "Keycloak EC2 이름 태그"
  type        = string
  default     = "keycloak-ec2"
}

variable "addon_kc_instance_type" {
  description = "EC2 인스턴스 타입. Keycloak(JVM) 은 t3.micro 에서 OOM 나므로 small 이상"
  type        = string
  default     = "t3.small"
}

variable "addon_kc_role_name" {
  description = "EC2 IAM 역할 이름 (인스턴스 프로파일은 <이름>-profile)"
  type        = string
  default     = "keycloak-ec2-role"
}

variable "addon_kc_image" {
  description = "Keycloak 컨테이너 이미지. 최신 안정 26.x — 과제지가 버전을 지정하면 그 태그로"
  type        = string
  default     = "quay.io/keycloak/keycloak:26.5"
}

variable "addon_kc_admin_username" {
  description = "부트스트랩 admin 사용자 이름 (KC_BOOTSTRAP_ADMIN_USERNAME)"
  type        = string
  default     = "admin"
}

variable "addon_kc_secret_name" {
  description = "admin 비밀번호를 저장할 Secrets Manager 시크릿 이름"
  type        = string
  default     = "keycloak/admin"
}

variable "addon_kc_hostname" {
  description = "KC_HOSTNAME (예: https://auth.example.com). 빈 값이면 hostname-strict=false + X-Forwarded 헤더로 ALB DNS 를 그대로 쓴다"
  type        = string
  default     = ""
}

# ----- ALB -----

variable "addon_kc_alb_name" {
  description = "ALB 이름 (32자 이하, 영숫자·하이픈만)"
  type        = string
  default     = "keycloak-alb"
}

variable "addon_kc_tg_name" {
  description = "타겟 그룹 이름"
  type        = string
  default     = "keycloak-tg"
}

# ----- RDS PostgreSQL (선택) -----

variable "addon_kc_rds_enabled" {
  description = "true 면 RDS PostgreSQL 을 만들고 KC_DB=postgres 로 연결한다. false 면 내장 dev-file DB (컨테이너 재생성 시 데이터 소실)"
  type        = bool
  default     = false
}

variable "addon_kc_db_identifier" {
  description = "RDS 인스턴스 식별자"
  type        = string
  default     = "keycloak-db"
}

variable "addon_kc_db_name" {
  description = "Keycloak 이 쓸 데이터베이스 이름"
  type        = string
  default     = "keycloak"
}

variable "addon_kc_db_username" {
  description = "RDS 마스터 사용자 이름"
  type        = string
  default     = "keycloak"
}

variable "addon_kc_db_engine_version" {
  description = "PostgreSQL 엔진 버전 (major 만 적으면 최신 minor 선택)"
  type        = string
  default     = "17"
}

variable "addon_kc_db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"
}
