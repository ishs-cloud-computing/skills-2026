# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_cwalarm_sns_topic_name" {
  description = "알람 통지 SNS 토픽 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "skills-alarm-topic"
}

variable "addon_cwalarm_email" {
  description = "이메일 구독 주소. 빈 문자열이면 구독을 만들지 않는다 (과제지 무요구 시 비워 둔다)"
  type        = string
  default     = ""
}

# ----- 로그 → 메트릭 필터 → 알람 -----
variable "addon_cwalarm_log_group_name" {
  description = "메트릭 필터를 걸 기존 로그 그룹 이름 (ECS awslogs·Container Insights application 등). 빈 문자열이면 로그 알람을 만들지 않는다"
  type        = string
  default     = ""
}

variable "addon_cwalarm_metric_namespace" {
  description = "로그 메트릭 네임스페이스. 채점 스크립트가 읽는 값이면 과제지 그대로"
  type        = string
  default     = "Skills/CloudComputing/Task1"
}

variable "addon_cwalarm_log_filters" {
  description = "로그 메트릭 필터·알람 묶음. key 는 terraform 식별자, 이름 3종은 과제지 명시값과 정확히 일치. pattern 은 앱 로그 형식에 맞춘다"
  type = map(object({
    filter_name = string
    metric_name = string
    alarm_name  = string
    pattern     = string
    threshold   = optional(number, 1)
  }))
  default = {
    "4xx" = {
      filter_name = "skills-4xx-filter"
      metric_name = "skills-4xx-count"
      alarm_name  = "skills-4xx-alarm"
      pattern     = "%status=4[0-9][0-9]%"
    }
    "5xx" = {
      filter_name = "skills-5xx-filter"
      metric_name = "skills-5xx-count"
      alarm_name  = "skills-5xx-alarm"
      pattern     = "%status=5[0-9][0-9]%"
    }
  }
}

# ----- AWS 네임스페이스 메트릭 알람 (ALB·RDS·Lambda·ECS·EKS·WAF REGIONAL) -----
variable "addon_cwalarm_metric_alarms" {
  description = "서비스 메트릭 알람 묶음. README 의 tfvars 예시에서 필요한 항목만 골라 넣는다. dimensions 값(ALB suffix·DB 식별자 등)은 기존 리소스 값"
  type = map(object({
    alarm_name          = string
    namespace           = string
    metric_name         = string
    dimensions          = map(string)
    statistic           = optional(string, "Sum")
    comparison_operator = optional(string, "GreaterThanOrEqualToThreshold")
    threshold           = number
    period              = optional(number, 60)
    evaluation_periods  = optional(number, 1)
    treat_missing_data  = optional(string, "notBreaching")
  }))
  default = {}
}

# ----- WAF CLOUDFRONT BlockedRequests (us-east-1 전용) -----
variable "addon_cwalarm_waf_cloudfront_name" {
  description = "CLOUDFRONT scope Web ACL 이름. 빈 문자열이면 us-east-1 알람·토픽을 만들지 않는다"
  type        = string
  default     = ""
}

variable "addon_cwalarm_waf_blocked_threshold" {
  description = "WAF BlockedRequests 알람 임계값 (period 당 Sum)"
  type        = number
  default     = 100
}
