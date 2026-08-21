# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_audit_role_name" {
  description = "Audit Role 이름. 채점 스크립트가 get-role 로 직접 읽으므로 과제지와 정확히 일치시킨다"
  type        = string
}

variable "addon_audit_external_id" {
  description = "sts:ExternalId 조건 값. 과제지가 선수 번호 등을 붙이라면 그대로 조립해 넣는다"
  type        = string
}

variable "addon_audit_policy_name" {
  description = "인라인 정책 이름"
  type        = string
  default     = "audit-policy"
}

variable "addon_audit_trusted_principal_arns" {
  description = "AssumeRole 허용 principal ARN 목록. 빈 목록이면 같은 계정 root(계정 내 모든 IAM principal)"
  type        = list(string)
  default     = []
}

variable "addon_audit_max_session_duration" {
  description = "최대 세션 시간 (초). 3600~43200"
  type        = number
  default     = 3600
}

variable "addon_audit_policy_statements" {
  description = "인라인 정책 statement 목록. 액션에 와일드카드를 쓰지 않는다. 기본값은 set-07 audit 정책 형태의 예시 — 과제지 요구로 교체"
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
  }))
  default = [
    {
      sid       = "DynamoRead"
      actions   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:DescribeTable"]
      resources = ["*"]
    },
    {
      sid       = "DescribeVpcAndCluster"
      actions   = ["ec2:DescribeVpcs", "eks:DescribeCluster"]
      resources = ["*"]
    },
  ]
}
