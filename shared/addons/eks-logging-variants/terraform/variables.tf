# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_ekslog_cluster_name" {
  description = "EKS 클러스터 이름. Control Plane 로그 그룹 /aws/eks/<이름>/cluster 와 EBS CSI 정책 이름에 쓴다"
  type        = string
}

variable "addon_ekslog_kms_alias" {
  description = "EKS 플랫폼 CMK alias (alias/ 접두어 제외). 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "eks-platform-key"
}

variable "addon_ekslog_kms_rotation_days" {
  description = "CMK 자동 회전 주기 (일). 과제지가 지정하면 그 값으로"
  type        = number
  default     = 365
}

variable "addon_ekslog_log_retention_days" {
  description = "Control Plane 로그 그룹 보존 일수"
  type        = number
  default     = 30
}

variable "addon_ekslog_create_cluster_log_group" {
  description = "true 면 /aws/eks/<cluster>/cluster 로그 그룹을 CMK 로 선생성한다 (eksctl 보다 먼저 apply). 클러스터가 이미 있으면 false 로 두고 README 의 associate-kms-key 로 간다"
  type        = bool
  default     = true
}
