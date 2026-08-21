# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ----- 룰 -----
variable "addon_evb_rules" {
  description = "만들 룰: key(eventbridge.tf 의 addon_evb_patterns 키) → 룰 이름(과제지 명시값). 필요한 키만 남긴다. 키: root_login iam_change sg_ingress ec2_modify ec2_state ebs_create guardduty"
  type        = map(string)
  default = {
    sg_ingress = "sg-ingress-rule"
    ec2_state  = "ec2-state-rule"
  }
}

variable "addon_evb_schedule_rules" {
  description = "스케줄 룰: 룰 이름 → schedule_expression (rate(5 minutes) / cron(0 9 * * ? *))"
  type        = map(string)
  default     = {}
}

variable "addon_evb_ec2_states" {
  description = "ec2_state 룰이 잡을 상태 목록 (pending running stopping stopped shutting-down terminated)"
  type        = list(string)
  default     = ["stopped", "terminated"]
}

variable "addon_evb_guardduty_min_severity" {
  description = "guardduty 룰 최소 severity (numeric >=). 4=Medium 7=High"
  type        = number
  default     = 4
}

# ----- 타깃 -----
variable "addon_evb_target_type" {
  description = "룰 타깃: sns(토픽 직접) 또는 lambda(공통 알림 핸들러 → SNS)"
  type        = string
  default     = "sns"
  validation {
    condition     = contains(["sns", "lambda"], var.addon_evb_target_type)
    error_message = "sns 또는 lambda"
  }
}

variable "addon_evb_sns_topic_name" {
  description = "알림 SNS 토픽 이름. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "security-alert-topic"
}

variable "addon_evb_email" {
  description = "email 구독 주소. 빈 문자열이면 구독 안 만듦"
  type        = string
  default     = ""
}

variable "addon_evb_lambda_name" {
  description = "알림 Lambda 함수 이름 (target_type = lambda 일 때)"
  type        = string
  default     = "security-alert-handler"
}

variable "addon_evb_lambda_runtime" {
  description = "Lambda 런타임. 과제지 명시 버전과 정확히 일치"
  type        = string
  default     = "python3.12"
}

# ----- GuardDuty -----
variable "addon_evb_guardduty_enabled" {
  description = "GuardDuty detector 생성 여부 (리전당 1개 — 이미 켜져 있으면 false)"
  type        = bool
  default     = false
}

# ----- AWS Config -----
variable "addon_evb_config_enabled" {
  description = "Config recorder·delivery channel·버킷 생성 여부 (리전당 recorder 1개 — 이미 있으면 false 로 두고 룰만)"
  type        = bool
  default     = false
}

variable "addon_evb_config_bucket_prefix" {
  description = "Config 딜리버리 버킷 이름 접두 (<prefix>-<account_id>)"
  type        = string
  default     = "config-logs"
}

variable "addon_evb_config_role_name" {
  description = "Config recorder IAM Role 이름"
  type        = string
  default     = "config-recorder-role"
}

variable "addon_evb_config_resource_types" {
  description = "recorder 기록 대상 리소스 타입. 빈 목록이면 all_supported"
  type        = list(string)
  default     = ["AWS::EC2::Instance", "AWS::EC2::SecurityGroup"]
}

variable "addon_evb_config_rules" {
  description = "Config 관리형 룰: key → {name(과제지 명시), source_identifier, input_parameters, resource_types}. 필요한 것만 남긴다 (빈 맵이면 룰 없음)"
  type = map(object({
    name              = string
    source_identifier = string
    input_parameters  = optional(map(string), {})
    resource_types    = optional(list(string), [])
  }))
  default = {
    ssh = {
      name              = "incoming-ssh-disabled"
      source_identifier = "INCOMING_SSH_DISABLED"
      resource_types    = ["AWS::EC2::SecurityGroup"]
    }
    tags = {
      name              = "required-tags"
      source_identifier = "REQUIRED_TAGS"
      input_parameters  = { tag1Key = "Project" }
      resource_types    = ["AWS::EC2::Instance"]
    }
    public_ip = {
      name              = "ec2-instance-no-public-ip"
      source_identifier = "EC2_INSTANCE_NO_PUBLIC_IP"
      resource_types    = ["AWS::EC2::Instance"]
    }
  }
}

variable "addon_evb_remediation_rule_key" {
  description = "SSM 자동 복구를 붙일 Config 룰 key (예: ssh). 빈 문자열이면 복구 없음. 예시 SSM 문서는 AWS-DisablePublicAccessForSecurityGroup — 다른 룰이면 config.tf 의 target_id·parameter 수정"
  type        = string
  default     = ""
}
