# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 채점(mark2.sh)이 정확 일치로 검사하는 이름·값은 전부 변수 (30% 변동 대비).
# 함수 JS(cloudfront/*.js) 안의 리터럴은 변수 미적용 — 치환 범위는 task-2/NOTES.md.

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name_prefix" {
  type    = string
  default = "skillsphone-landing-ab-"
}

variable "kvs_name" {
  type    = string
  default = "skillsphone-cdn-ab-config"
}

variable "req_fn_name" {
  type    = string
  default = "skillsphone-cdn-ab-req-fn"
}

variable "res_fn_name" {
  type    = string
  default = "skillsphone-cdn-ab-res-fn"
}

variable "cache_policy_name" {
  type    = string
  default = "skillsphone-cdn-ab-cache-policy"
}

variable "response_headers_policy_name" {
  type    = string
  default = "skillsphone-cdn-ab-security-headers"
}

variable "distribution_name" {
  type    = string
  default = "skillsphone-cdn-ab-distribution"
}

variable "ab_cookie_name" {
  type    = string
  default = "x-sp-ab"
}

variable "ab_weight" {
  type    = string
  default = "0.3"
}

variable "version_a_path" {
  type    = string
  default = "/version-a/index.html"
}

variable "version_b_path" {
  type    = string
  default = "/version-b/index.html"
}
