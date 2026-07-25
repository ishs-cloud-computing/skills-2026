# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 대회에서 바뀌기 쉬운 값은 여기서 주입한다 (CLAUDE.md 변수 규칙).
# 값은 variables.tf default 와 동일 — 대회 당일 이름/비율 변경 시 이 파일만 수정한다.
region            = "us-east-1"
bucket_prefix     = "skillsphone-landing-ab"
kvs_name          = "skillsphone-cdn-ab-config"
req_fn_name       = "skillsphone-cdn-ab-req-fn"
res_fn_name       = "skillsphone-cdn-ab-res-fn"
cache_policy_name = "skillsphone-cdn-ab-cache-policy"

response_headers_policy_name = "skillsphone-cdn-ab-security-headers-policy"
oac_name                     = "skillsphone-cdn-ab-oac"
distribution_comment         = "skillsphone-cdn-ab-distribution"
ab_weight                    = "0.3"
version_a_path               = "/version-a/index.html"
version_b_path               = "/version-b/index.html"
