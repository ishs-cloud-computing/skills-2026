# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "bibunho" {
  description = "선수 비번호 (S3 버킷명 suffix, terraform.tfvars로 주입)"
  type        = string
}

variable "region" {
  description = "과제 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  description = "고정 리소스명 공통 prefix"
  type        = string
  default     = "skills-book"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public Subnet CIDR 목록 (azs와 순서 대응)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private Subnet CIDR 목록 (azs와 순서 대응)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "azs" {
  description = "사용할 가용영역"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "nat_gateway_count" {
  description = "NAT Gateway 개수 (2=AZ별 HA, 1=비용 절감)"
  type        = number
  default     = 2
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
  description = "Fargate Task CPU (최소 사양 요구)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate Task Memory (MiB)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "ECS Service Desired Count"
  type        = number
  default     = 2
}

variable "image_tag" {
  description = "ECR 이미지 태그"
  type        = string
  default     = "v1"
}

variable "table_name" {
  description = "DynamoDB 테이블명 (컨테이너 env TABLE_NAME과 단일 소스)"
  type        = string
  default     = "skills-book-booking"
}

variable "origin_verify_header" {
  description = "CloudFront -> ALB Origin 검증 헤더명"
  type        = string
  default     = "X-Origin-Verify"
}

variable "log_stream_prefix" {
  description = "awslogs 스트림 prefix"
  type        = string
  default     = "book"
}

variable "metric_namespace" {
  description = "4xx/5xx 메트릭 네임스페이스"
  type        = string
  default     = "Skills/CloudComputing/Task1"
}

locals {
  vpc_name            = "${var.name_prefix}-vpc"
  bucket_name         = "${var.name_prefix}-static-2026-${var.bibunho}"
  cloudfront_name     = "${var.name_prefix}-cloudfront"
  alb_name            = "${var.name_prefix}-alb"
  tg_name             = "${var.name_prefix}-tg"
  ecr_name            = "${var.name_prefix}-ecr"
  cluster_name        = "${var.name_prefix}-cluster"
  service_name        = "${var.name_prefix}-service"
  task_family         = "${var.name_prefix}-task"
  container_name      = "${var.name_prefix}-container"
  execution_role_name = "${var.name_prefix}-ecs-execution-role"
  task_role_name      = "${var.name_prefix}-ecs-task-role"
  log_group_name      = "/ecs/${var.name_prefix}-app"
  kms_alias           = "alias/${var.name_prefix}-ddb"
  filter_4xx_name     = "${var.name_prefix}-4xx-filter"
  filter_5xx_name     = "${var.name_prefix}-5xx-filter"
  metric_4xx_name     = "${var.name_prefix}-4xx-count"
  metric_5xx_name     = "${var.name_prefix}-5xx-count"
  alarm_4xx_name      = "${var.name_prefix}-4xx-alarm"
  alarm_5xx_name      = "${var.name_prefix}-5xx-alarm"

  s3_origin_id  = "s3-static"
  alb_origin_id = "alb-api"

  provided_dir = "${path.module}/../../../shared/provided/task-1"
}
