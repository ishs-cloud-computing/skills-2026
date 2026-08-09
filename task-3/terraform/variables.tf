# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "prefix" {
  description = "모든 리소스 이름의 대표 접두사. locals.tf의 이름이 전부 여기서 파생된다."
  type        = string
  default     = "skills"
}

variable "bucket_name" {
  description = "product 이미지 S3 버킷 이름. 전역 유일이라 prefix 파생에서 빠지며, 안전한 default가 없어 tfvars 누락 시 apply가 즉시 실패한다."
  type        = string
}

variable "db_identifier" {
  description = "RDS DB identifier. 과제지 명시값을 정확일치로 채점하므로 prefix 파생에서 빠진다."
  type        = string
  default     = "apdev-rds-instance"
}

variable "apps" {
  description = "앱 목록. ECR 레포가 이 목록에서 생성되고 레포명이 k8s 매니페스트의 이미지명과 정확히 일치해야 한다."
  type        = list(string)
  default     = ["user", "product", "stress"]
}

variable "image_tag" {
  description = "컨테이너 이미지 태그"
  type        = string
  default     = "v1"
}

variable "db_password" {
  description = "RDS master 비밀번호"
  type        = string
  sensitive   = true
}
