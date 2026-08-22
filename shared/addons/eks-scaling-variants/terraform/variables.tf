# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_ekscale_cluster_name" {
  description = "EKS 클러스터 이름. interruption 큐 이름 기본값이자 helm settings.clusterName"
  type        = string
}

variable "addon_ekscale_queue_name" {
  description = "Karpenter interruption SQS 큐 이름. 빈 문자열이면 클러스터 이름을 쓴다 (공식 CloudFormation 관례). helm settings.interruptionQueue 와 일치"
  type        = string
  default     = ""
}

variable "addon_ekscale_karpenter_role_name" {
  description = "Karpenter 컨트롤러 IAM Role 이름 (eksctl iamserviceaccount 가 만든 역할). 비우면 정책만 만들고 attach 하지 않는다"
  type        = string
  default     = ""
}
