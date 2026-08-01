# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark2-3.sh)이 이름·태그 정확 일치로 검사하는 값 전부 변수 (30% 변동 대비).

variable "region" {
  description = "Cloud Event Handling 모듈 리전 (과제지 5)"
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_name" {
  description = "VPC Name 태그 (채점 3-1)"
  type        = string
  default     = "skills-ceh-vpc"
}

variable "vpc_cidr" {
  description = "과제지 5-1"
  type        = string
  default     = "10.73.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.73.0.0/24"
}

variable "az" {
  description = "단일 AZ 배치 (과제지 무요구 — 최소 구성)"
  type        = string
  default     = "ap-southeast-1a"
}

variable "ec2_name" {
  description = "채점 3-1"
  type        = string
  default     = "skills-ceh-ec2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "protected_sg_name" {
  description = "보호 대상 SG Name 태그 (채점 3-1·3-2·3-5)"
  type        = string
  default     = "skills-ceh-protected-sg"
}

variable "topic_name" {
  description = "채점 3-3"
  type        = string
  default     = "skills-ceh-alert-topic"
}

variable "lambda_function_name" {
  description = "채점 3-3·3-4·3-5"
  type        = string
  default     = "skills-ceh-remediate-fn"
}

variable "lambda_timeout" {
  description = "과제지 5-3: 30초 이상"
  type        = number
  default     = 30
}

variable "trail_name" {
  description = "채점 3-4"
  type        = string
  default     = "skills-ceh-cloudtrail"
}

variable "rule_name" {
  description = "채점 3-4"
  type        = string
  default     = "skills-ceh-sg-change-rule"
}
