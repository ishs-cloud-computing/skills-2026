# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_asg_name" {
  description = "Auto Scaling Group 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "wsc2026-app-asg"
}

variable "addon_asg_instance_name" {
  description = "ASG 가 띄우는 인스턴스 Name 태그 (propagate_at_launch)"
  type        = string
  default     = "wsc2026-app"
}

variable "addon_asg_instance_type" {
  description = "인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "addon_asg_subnet_ids" {
  description = "ASG 배치 서브넷 ID 목록 (기존 프라이빗 서브넷, 2AZ 이상). 같은 state 면 [aws_subnet.this[\"...\"].id, ...] 로 바꾼다"
  type        = list(string)
}

variable "addon_asg_security_group_ids" {
  description = "인스턴스 SG ID 목록 (기존 앱 SG). 같은 state 면 [aws_security_group.app.id] 로 바꾼다"
  type        = list(string)
}

variable "addon_asg_instance_profile_name" {
  description = "기존 인스턴스 프로파일 이름 (SSM·앱 권한). 같은 state 면 aws_iam_instance_profile.app.name 으로 바꾼다"
  type        = string
}

variable "addon_asg_target_group_arns" {
  description = "기존 ALB 대상 그룹 ARN 목록. 같은 state 면 [aws_lb_target_group.app.arn] 로 바꾼다"
  type        = list(string)
  default     = []
}

variable "addon_asg_user_data_base64" {
  description = "base64 인코딩된 user data. tfvars 는 함수를 못 쓰므로 보통 ec2-asg.tf 의 local 에서 base64encode(templatefile(...)) 로 덮어쓴다"
  type        = string
  default     = ""
}

variable "addon_asg_min_size" {
  description = "최소 인스턴스 수"
  type        = number
  default     = 2
}

variable "addon_asg_max_size" {
  description = "최대 인스턴스 수"
  type        = number
  default     = 4
}

variable "addon_asg_desired_capacity" {
  description = "희망 인스턴스 수"
  type        = number
  default     = 2
}

variable "addon_asg_health_check_grace_period" {
  description = "ELB 헬스체크 유예(초). user_data 설치 시간보다 길게"
  type        = number
  default     = 300
}

variable "addon_asg_cpu_target" {
  description = "target tracking 목표 평균 CPU(%)"
  type        = number
  default     = 50
}

variable "addon_asg_root_volume_size" {
  description = "루트 볼륨 크기(GiB)"
  type        = number
  default     = 30
}
