variable "player_number" {
  description = "대회 비번호"
  type        = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "azs" {
  description = "Region AZ"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "cluster_name" {
  type    = string
  default = "skills-eks"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.2.0/24", "10.0.3.0/24"]
}

# ── 앱 목록: ECR 레포·ALB 타깃그룹·리스너 규칙이 전부 이 맵에서 생성된다.
# 당일 API 추가/삭제 = 여기 한 항목 + k8s/1X-<app>.yaml 복사/삭제.
variable "apps" {
  description = "서비스할 API 앱. path는 ALB 경로 규칙, priority는 규칙 우선순위."
  type = map(object({
    path        = string
    priority    = number
    port        = optional(number, 8080)
    health_path = optional(string, "/healthcheck")
  }))
  default = {
    user    = { path = "/v1/user", priority = 10 }
    product = { path = "/v1/product", priority = 20 }
    stress  = { path = "/v1/stress", priority = 30 }
  }
}

# ── DB: 당일 엔진 변경(예: PostgreSQL) 시 engine/engine_version/port/username만 수정.
# rds.tf·rds-proxy.tf만 이 변수를 참조하고 다른 리소스는 DB를 참조하지 않으므로
# apply 시 DB 스택만 재생성된다 (ALB·CloudFront·EKS는 no-op).
variable "db_identifier" {
  description = "과제지에 명시된 DB identifier"
  type        = string
  default     = "apdev-rds-instance"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_engine" {
  description = "mysql 또는 postgres (proxy engine_family가 자동 파생됨)"
  type        = string
  default     = "mysql"
}

variable "db_engine_version" {
  type    = string
  default = "8.0"
}

variable "db_name" {
  description = "논리 데이터베이스 이름 (앱의 MYSQL_DBNAME)"
  type        = string
  default     = "dev"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  description = "RDS master 비밀번호"
  type        = string
  sensitive   = true
  default     = "password"
}

variable "db_port" {
  description = "mysql 3306, postgres 5432"
  type        = number
  default     = 3306
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_allocated_storage" {
  description = "gp3 스토리지(GB). 이 워크로드는 버퍼풀+PK/인덱스 조회라 baseline 3000 IOPS로 충분."
  type        = number
  default     = 20
}

# ── WAF: requestid/uuid 쿼리스트링 누락 차단 룰 토글.
# 기본 count — 당일 실트래픽의 쿼리스트링을 관찰한 뒤 -var waf_v1_block_enabled=true로 활성.
variable "waf_v1_block_enabled" {
  type    = bool
  default = false
}
