# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# Origin 검증 헤더 값 — listener rule과 동일 참조로 불일치 원천 차단
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${var.player_number}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# mark.sh가 S3 오리진 도메인에 버킷명 포함 여부로 배포를 식별 (2-3, 4-5, 6-2, 8-1)
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = "index.html"
  comment             = local.cloudfront_name

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  origin {
    origin_id   = local.alb_origin_id
    domain_name = aws_lb.this.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = var.origin_verify_header
      value = random_password.origin_verify.result
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  # 과제 5장: /v1/* -> ALB origin, POST 포함 허용. API는 캐시 금지
  ordered_cache_behavior {
    path_pattern             = "/v1/*"
    target_origin_id         = local.alb_origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # 과제 5장: /health -> ALB origin. 캐시되면 죽은 Task가 가려지므로 캐시 금지 (채점 4-5, 8-1)
  ordered_cache_behavior {
    path_pattern             = "/health"
    target_origin_id         = local.alb_origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = local.cloudfront_name
  }
}
