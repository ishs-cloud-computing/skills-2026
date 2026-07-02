variable "player_number" {
  description = "선수 비번호 — 모든 리소스명의 prefix (terraform.tfvars로 주입)"
  type        = string
}

variable "region" {
  description = "과제 리전 (컨테이너 env AWS_REGION과 단일 소스)"
  type        = string
  default     = "ap-northeast-2"
}

variable "azs" {
  description = "사용할 가용영역 (과제지: 2a, 2c)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "vpc_cidr" {
  description = "VPC CIDR (과제지 고정값)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public Subnet CIDR 목록 (azs와 순서 대응, 과제지 고정값)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "container_port" {
  description = "Book 앱 리스닝 포트 (TG/SG/Task Definition 공유)"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "ALB Target Group Health Check 경로"
  type        = string
  default     = "/health"
}

variable "task_cpu" {
  description = "Fargate Task CPU (과제지 고정: 256)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate Task Memory MiB (과제지 고정: 512)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "ECS Service Desired Count (과제 요구 1 이상 — 2로 AZ 분산)"
  type        = number
  default     = 2
}

variable "image_tag" {
  description = "ECR 이미지 태그 (과제지 고정: latest)"
  type        = string
  default     = "latest"
}

variable "log_group_name" {
  description = "CloudWatch Logs 로그 그룹 (과제지 고정 — 선수ID prefix 예외)"
  type        = string
  default     = "/skillskorea/ecs/app"
}

variable "log_stream_prefix" {
  description = "awslogs 스트림 prefix (채점: ecs/ 접두어 스트림 요구)"
  type        = string
  default     = "ecs"
}

variable "origin_verify_header" {
  description = "CloudFront -> ALB Origin 검증 헤더명"
  type        = string
  default     = "X-Origin-Verify"
}

locals {
  vpc_name            = "${var.player_number}-vpc"
  igw_name            = "${var.player_number}-igw"
  public_rt_name      = "${var.player_number}-public-rt"
  bucket_name         = "${var.player_number}-static-site"
  cloudfront_name     = "${var.player_number}-book-cf"
  alb_name            = "${var.player_number}-book-alb"
  alb_sg_name         = "${var.player_number}-alb-sg"
  ecs_sg_name         = "${var.player_number}-ecs-sg"
  tg_name             = "${var.player_number}-book-tg"
  ecr_name            = "${var.player_number}-book-ecr"
  cluster_name        = "${var.player_number}-book-cluster"
  service_name        = "${var.player_number}-book-service"
  task_family         = "${var.player_number}-book-task"
  container_name      = "book"
  table_name          = "${var.player_number}-booking-table"
  execution_role_name = "${var.player_number}-ecs-execution-role"
  task_role_name      = "${var.player_number}-ecs-task-role"

  s3_origin_id  = "s3-static"
  alb_origin_id = "alb-api"

  provided_dir = "${path.module}/../../../shared/provided/task-1"
}
