# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudFront Distribution (과제지 2. CDN Function - 5, 채점 2-3~2-6)
# - Comment 로 식별 (채점이 Comment == skillsphone-cdn-ab-distribution 조회)
# - S3 origin + OAC, HTTP→HTTPS redirect, 함수 2개 + 커스텀 정책 연결
# - Pay-as-you-go(기본 과금) — 별도 설정 필드 없음
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "landing" {
  name                              = "skillsphone-cdn-ab-oac"
  description                       = "OAC for landing bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = var.distribution_comment

  origin {
    origin_id                = "s3-landing"
    domain_name              = aws_s3_bucket.landing.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.landing.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-landing"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id            = aws_cloudfront_cache_policy.ab.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.request.arn
    }

    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.response.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = var.distribution_comment }
}
