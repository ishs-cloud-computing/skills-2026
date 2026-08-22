# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_wafx_name" {
  description = "룰을 붙일 Web ACL 이름. rules.tf 예시 ACL 과 regex set·metric 이름 접두에 쓴다. 과제지 명시 이름과 정확히 일치"
  type        = string
  default     = "skills-waf"
}

variable "addon_wafx_scope" {
  description = "REGIONAL(ALB/API GW) 또는 CLOUDFRONT. CLOUDFRONT 면 rules.tf 의 리소스 전부에 provider = aws.use1 추가"
  type        = string
  default     = "REGIONAL"
}

variable "addon_wafx_block_body" {
  description = "차단 응답 본문 문자열. 과제지가 403 + 지정 문자열을 요구할 때 그대로 넣는다"
  type        = string
  default     = "Request blocked by WAF"
}

variable "addon_wafx_common_count_rules" {
  description = "AWSManagedRulesCommonRuleSet 중 COUNT 로 강등할 룰 이름(오탐 방지). 예: SizeRestrictions_BODY, NoUserAgent_HEADER"
  type        = list(string)
  default     = ["SizeRestrictions_BODY"]
}

variable "addon_wafx_api_path_regexes" {
  description = "검사 대상 경로 regex 목록(regex pattern set). 여기 없는 경로는 WAF 가 판정하지 않는다"
  type        = list(string)
  default     = ["^/v1/.*$", "^/health$"]
}

variable "addon_wafx_rate_limit" {
  description = "rate-based rule 임계 요청 수(evaluation window 당 IP 기준). 최소 10"
  type        = number
  default     = 100
}

variable "addon_wafx_rate_window_sec" {
  description = "rate-based rule 평가 윈도(초). 60/120/300/600 만 허용"
  type        = number
  default     = 60
}

variable "addon_wafx_rate_path_regex" {
  description = "rate-based rule 의 scope_down 경로 regex(인라인). 빈 문자열이면 전 경로"
  type        = string
  default     = "^/v1/.*$"
}

variable "addon_wafx_geo_country_codes" {
  description = "geo_match 로 차단할 ISO 3166-1 alpha-2 국가 코드"
  type        = list(string)
  default     = ["CN", "RU"]
}

variable "addon_wafx_post_body_strings" {
  description = "POST body 에 포함되면 차단할 문자열(LOWERCASE 변환 후 CONTAINS)"
  type        = list(string)
  default     = ["admin", "sysop"]
}

variable "addon_wafx_header_name" {
  description = "헤더 조건 룰이 검사할 헤더 이름(소문자)"
  type        = string
  default     = "x-api-key"
}

variable "addon_wafx_header_value" {
  description = "헤더 조건 룰의 기대 값. 이 값과 다르면(없으면) 차단"
  type        = string
  default     = "changeme"
}

variable "addon_wafx_ua_regexes" {
  description = "차단할 User-Agent regex 목록(LOWERCASE 변환 후 검사). 스캐너 UA 패턴"
  type        = list(string)
  default     = ["sqlmap", "nikto", "nmap", "masscan"]
}
