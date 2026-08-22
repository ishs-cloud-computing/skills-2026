# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_cwdash_name" {
  description = "대시보드 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "skills-dashboard"
}

variable "addon_cwdash_region" {
  description = "ALB·RDS·ECS·EKS·Lambda 위젯이 읽는 메트릭 리전 (대시보드 자체는 리전 무관)"
  type        = string
  default     = "ap-northeast-2"
}

variable "addon_cwdash_period" {
  description = "위젯 공통 집계 주기 (초)"
  type        = number
  default     = 60
}

# ----- 위젯별 dimension. 빈 문자열이면 해당 위젯을 넣지 않는다 -----
variable "addon_cwdash_alb_arn_suffix" {
  description = "ALB LoadBalancer dimension (aws_lb.<기존>.arn_suffix = app/<이름>/<id>)"
  type        = string
  default     = ""
}

variable "addon_cwdash_rds_instance_id" {
  description = "RDS DBInstanceIdentifier dimension"
  type        = string
  default     = ""
}

variable "addon_cwdash_ecs_cluster_name" {
  description = "ECS ClusterName dimension. service 와 둘 다 비어 있지 않아야 위젯이 들어간다"
  type        = string
  default     = ""
}

variable "addon_cwdash_ecs_service_name" {
  description = "ECS ServiceName dimension"
  type        = string
  default     = ""
}

variable "addon_cwdash_eks_cluster_name" {
  description = "EKS ContainerInsights ClusterName dimension (amazon-cloudwatch-observability addon 필요)"
  type        = string
  default     = ""
}

variable "addon_cwdash_lambda_function_name" {
  description = "Lambda FunctionName dimension"
  type        = string
  default     = ""
}

variable "addon_cwdash_waf_acl_name" {
  description = "WAF WebACL dimension (Web ACL 이름)"
  type        = string
  default     = ""
}

variable "addon_cwdash_waf_metric_region" {
  description = "WAF BlockedRequests 메트릭이 있는 리전. CLOUDFRONT scope 는 us-east-1, REGIONAL 은 ALB 리전"
  type        = string
  default     = "us-east-1"
}

variable "addon_cwdash_waf_dimension_region" {
  description = "WAF Region dimension 값. CLOUDFRONT scope 는 Global, REGIONAL 은 리전 코드(ap-northeast-2)"
  type        = string
  default     = "Global"
}
