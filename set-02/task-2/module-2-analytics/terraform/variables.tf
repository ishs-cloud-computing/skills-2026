variable "region" {
  description = "모듈 2 리전 (과제지: ap-northeast-2)"
  type        = string
  default     = "ap-northeast-2"
}

variable "player_number" {
  description = "비번호 (이 모듈의 채점 이름에는 쓰이지 않지만 태깅·식별용)"
  type        = string
  default     = "103"
}

# ----- Network (과제지 1. VPC) -----

variable "vpc_name" {
  description = "VPC 이름"
  type        = string
  default     = "analytics-vpc"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnets" {
  description = "서브넷 정의. Name 태그는 mark 2-1 이 정확 일치로 채점한다"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "analytics-pub-a"  = { cidr = "10.20.0.0/24", az = "ap-northeast-2a", tier = "public" }
    "analytics-pub-b"  = { cidr = "10.20.1.0/24", az = "ap-northeast-2b", tier = "public" }
    "analytics-priv-a" = { cidr = "10.20.100.0/24", az = "ap-northeast-2a", tier = "private" }
    "analytics-priv-b" = { cidr = "10.20.101.0/24", az = "ap-northeast-2b", tier = "private" }
  }
}

variable "igw_name" {
  description = "인터넷 게이트웨이 이름"
  type        = string
  default     = "analytics-igw"
}

variable "nat_name" {
  description = "NAT 게이트웨이 이름 (단일 NAT, analytics-pub-a 배치)"
  type        = string
  default     = "analytics-ngw"
}

variable "nat_subnet_name" {
  description = "NAT 게이트웨이를 배치할 퍼블릭 서브넷 이름"
  type        = string
  default     = "analytics-pub-a"
}

variable "pub_rtb_name" {
  description = "퍼블릭 라우트 테이블 이름 (두 퍼블릭 서브넷 공용)"
  type        = string
  default     = "analytics-pub-rtb"
}

variable "priv_rtb_names" {
  description = "프라이빗 서브넷별 라우트 테이블 이름 (key = 서브넷 이름)"
  type        = map(string)
  default = {
    "analytics-priv-a" = "analytics-priv-a-rtb"
    "analytics-priv-b" = "analytics-priv-b-rtb"
  }
}

# ----- EC2 / App (과제지 2. EC2, Application.md) -----

variable "instance_name" {
  description = "애플리케이션 EC2 이름 태그 (mark 2-1/2-6 이 이 태그로 인스턴스를 찾는다)"
  type        = string
  default     = "wsc2026-analytics-ec2"
}

variable "instance_type" {
  description = "애플리케이션 EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "app_subnet_name" {
  description = "EC2 를 배치할 프라이빗 서브넷 (mark 2-1: analytics-priv-a)"
  type        = string
  default     = "analytics-priv-a"
}

variable "app_port" {
  description = "Flask/gunicorn 애플리케이션 포트 (Application.md, mark 2-2 TG 포트)"
  type        = number
  default     = 5000
}

# 2026-08-21 신판이 원문 오타를 고쳤다 — 정본은 "wsc2026-analytics-ec2-role" 이다.
# 전사본(task.md)은 신판을 따랐고 여기는 아직 구판 이름이라 어긋나 있다. 리네임은 이슈 #133.
variable "ec2_role_name" {
  description = "애플리케이션 EC2 IAM 역할 이름 (과제지 6. IAM — 신판은 analytics, 리네임 #133)"
  type        = string
  default     = "wsc2026-alaytics-ec2-role"
}

# ----- ALB (과제지 3. Load Balancer) -----

variable "alb_name" {
  description = "ALB 이름 (mark2-2.sh 가 이 이름으로 DNS 를 조회)"
  type        = string
  default     = "wsc2026-analytics-alb"
}

variable "tg_name" {
  description = "타겟 그룹 이름 (mark 2-2)"
  type        = string
  default     = "wsc2026-analytics-tg"
}

# ----- Kinesis / Flink (과제지 4. Kinesis, 5. Managed Flink) -----

variable "stream_name" {
  description = "주문 로그 Kinesis Data Stream 이름 (mark 2-3-A)"
  type        = string
  default     = "wsc2026-order-stream"
}

variable "flink_app_name" {
  description = "Managed Flink Studio Notebook 이름 (mark 2-4)"
  type        = string
  default     = "wsc2026-analytics-flink"
}

variable "flink_role_name" {
  description = "Managed Flink 서비스 실행 역할 이름 (과제지 6. IAM)"
  type        = string
  default     = "wsc2026-analytics-flink-role"
}

variable "flink_runtime" {
  description = "Studio Notebook 런타임. task.md 는 'Flink 1.19' 라고 쓰지만 mark 2-4 는 ZEPPELIN-FLINK-3_0 을 채점한다"
  type        = string
  default     = "ZEPPELIN-FLINK-3_0"
}

variable "glue_db_name" {
  description = "Studio Notebook 이 테이블 DDL 을 저장할 Glue 데이터베이스 (소문자/언더스코어만 허용)"
  type        = string
  default     = "wsc2026_analytics_db"
}

# ----- Bastion (유의사항: 채점은 Bastion/CloudShell 에서 수행) -----

variable "bastion_instance_type" {
  description = "Bastion 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "ssh_password" {
  description = "Bastion ec2-user SSH 패스워드"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}
