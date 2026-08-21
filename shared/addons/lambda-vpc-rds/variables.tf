# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_lamvpc_function_name" {
  description = "Lambda 함수 이름. 과제지 명시 이름과 정확히 일치. 역할·SG·로그 그룹 이름이 여기서 파생된다"
  type        = string
}

variable "addon_lamvpc_runtime" {
  description = "Lambda 런타임. 과제지 명시 버전으로. pymysql 은 순수 파이썬이라 버전 무관"
  type        = string
  default     = "python3.13"
}

variable "addon_lamvpc_vpc_id" {
  description = "기존 VPC ID (Lambda SG 생성용)"
  type        = string
}

variable "addon_lamvpc_subnet_ids" {
  description = "Lambda ENI 를 둘 기존 private 서브넷 ID 목록 (RDS Proxy 와 같은 VPC)"
  type        = list(string)
}

variable "addon_lamvpc_db_sg_id" {
  description = "기존 RDS/Proxy SG ID. 이 SG 에 Lambda SG → DB 포트 인바운드를 추가한다. 이미 0.0.0.0/0 이면 빈 문자열로 생략"
  type        = string
  default     = ""
}

variable "addon_lamvpc_db_port" {
  description = "DB 포트"
  type        = number
  default     = 3306
}

variable "addon_lamvpc_proxy_endpoint" {
  description = "기존 RDS Proxy 엔드포인트 호스트명 (aws_db_proxy.<x>.endpoint)"
  type        = string
}

variable "addon_lamvpc_db_name" {
  description = "접속 DB 이름"
  type        = string
  default     = "dev"
}

variable "addon_lamvpc_secret_arn" {
  description = "DB 자격증명 Secrets Manager 시크릿 ARN ({username,password} JSON). Proxy 가 쓰는 시크릿과 같은 것"
  type        = string
}

variable "addon_lamvpc_table" {
  description = "조회 대상 테이블 이름 (SQL 식별자 — 영숫자·_ 만)"
  type        = string
  default     = "product"
}

variable "addon_lamvpc_key_column" {
  description = "쿼리스트링 필수 파라미터 = WHERE 컬럼 이름 (SQL 식별자 — 영숫자·_ 만)"
  type        = string
  default     = "id"
}

variable "addon_lamvpc_url_auth_type" {
  description = "Function URL 인증. CloudFront OAC 뒤면 AWS_IAM, 직접 노출이면 NONE"
  type        = string
  default     = "AWS_IAM"
}

variable "addon_lamvpc_log_retention_days" {
  description = "로그 그룹 보존 기간(일)"
  type        = number
  default     = 7
}
