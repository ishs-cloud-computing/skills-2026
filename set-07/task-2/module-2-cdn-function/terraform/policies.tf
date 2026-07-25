# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Policy (과제지 2. CDN Function - 4, 채점 2-3)
# 캐시 키에 x-sp-ab 쿠키를 whitelist 해야 A/B 버전이 서로 다른 캐시 항목으로 보관된다.
# AWS Managed Policy 는 쓰지 않는다 (과제지 명시).
# ---------------------------------------------------------------------------

resource "aws_cloudfront_cache_policy" "ab" {
  name    = var.cache_policy_name
  comment = "A/B cache split by x-sp-ab cookie"

  min_ttl     = 0
  default_ttl = 300
  max_ttl     = 3600

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "whitelist"
      cookies {
        items = ["x-sp-ab"]
      }
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name    = var.response_headers_policy_name
  comment = "Security headers for landing responses"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    xss_protection {
      protection = true
      mode_block = true
      override   = true
    }
  }
}
