# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_cwli_name_prefix" {
  description = "저장 쿼리 이름 접두. 콘솔에는 <접두>/app/..., <접두>/waf/... 폴더로 보인다. 과제지가 이름을 지정하면 그 값"
  type        = string
  default     = "skills"
}

variable "addon_cwli_app_log_group_names" {
  description = "앱 로그 쿼리 대상 로그 그룹 (ECS awslogs `/ecs/<앱>` · Container Insights `/aws/containerinsights/<클러스터>/application` 등). 비어 있으면 앱 쿼리를 만들지 않는다"
  type        = list(string)
  default     = []
}

variable "addon_cwli_waf_log_group_names" {
  description = "WAF 로그 그룹 (`aws-waf-logs-*`). CLOUDFRONT scope 는 us-east-1 에 있으므로 쿼리 정의도 aws.use1 로 만든다. 비어 있으면 WAF 쿼리를 만들지 않는다"
  type        = list(string)
  default     = []
}
