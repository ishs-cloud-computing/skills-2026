# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "region" {
  description = "CDN Function 모듈 리전"
  type        = string
  default     = "us-east-1"
}

# 과제지 표와 정확히 일치 (이름 일치 채점 2-1~2-3). 버킷 이름은 <prefix>-<ACCOUNT_ID>.
variable "bucket_prefix" {
  description = "랜딩 페이지 버킷 이름 prefix (계정 ID 가 뒤에 붙는다)"
  type        = string
  default     = "skillsphone-landing-ab"
}

variable "kvs_name" {
  description = "A/B 설정 KeyValueStore 이름"
  type        = string
  default     = "skillsphone-cdn-ab-config"
}

variable "req_fn_name" {
  description = "viewer-request 함수 이름"
  type        = string
  default     = "skillsphone-cdn-ab-req-fn"
}

variable "res_fn_name" {
  description = "viewer-response 함수 이름"
  type        = string
  default     = "skillsphone-cdn-ab-res-fn"
}

variable "cache_policy_name" {
  description = "커스텀 캐시 정책 이름"
  type        = string
  default     = "skillsphone-cdn-ab-cache-policy"
}

variable "response_headers_policy_name" {
  description = "커스텀 Security Header 정책 이름"
  type        = string
  default     = "skillsphone-cdn-ab-security-headers-policy"
}

variable "oac_name" {
  description = "S3 origin 용 OAC 이름 (채점 대상 아님)"
  type        = string
  default     = "skillsphone-cdn-ab-oac"
}

variable "distribution_comment" {
  description = "배포 식별용 Comment (채점이 Comment 로 배포를 찾는다)"
  type        = string
  default     = "skillsphone-cdn-ab-distribution"
}

variable "ab_weight" {
  description = "B 버전 노출 비율 (KVS weight 키 값)"
  type        = string
  default     = "0.3"
}

variable "version_a_path" {
  description = "A 버전 URI (KVS version_a 값 = S3 오브젝트 키 앞에 / 붙인 것)"
  type        = string
  default     = "/version-a/index.html"
}

variable "version_b_path" {
  description = "B 버전 URI (KVS version_b 값)"
  type        = string
  default     = "/version-b/index.html"
}
