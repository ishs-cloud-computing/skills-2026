# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudFront (요구사항 11)
# - wskorea26-concert-cf (mark 는 Comment 로 배포를 식별한다)
# - Origin: wskorea26-alb-origin(커스텀, X-Origin-Verify 헤더 주입)
#           wskorea26-s3-origin(OAC, origin_path=/web/main, wskorea26-s3-access 헤더)
# - 기본 동작: S3 정적 캐싱(CachingOptimized) + redirect-to-https (mark 8-3/8-5)
# - /book*  : ALB 로 무캐싱 전달(쿼리/바디 포함) + POST 경로 재작성 CF Function (mark 9-x)
# - PriceClass_All : 전세계 사용자 빠른 접근 (요구사항 11)
# ---------------------------------------------------------------------------

resource "aws_cloudfront_function" "book_rewrite" {
  name    = "wskorea26-book-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite POST /book to /v1/book for the book app"
  publish = true
  code    = file("${path.module}/cloudfront/book-rewrite.js")
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "wskorea26-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS 관리형 캐시/오리진 요청 정책
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  comment             = var.cloudfront_name
  price_class         = "PriceClass_All"
  default_root_object = "index.html"

  # ----- wskorea26-alb-origin -----
  origin {
    origin_id   = var.alb_origin_id
    domain_name = aws_lb.book.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # ALB 리스너 규칙이 이 헤더를 검증한다 (요구사항 11, mark 7-2 / 8-4)
    custom_header {
      name  = var.origin_verify_header
      value = var.origin_verify_value
    }
  }

  # ----- wskorea26-s3-origin -----
  origin {
    origin_id                = var.s3_origin_id
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
    # 루트(/) -> web/main/index.html, /main.jpeg -> web/main/main.jpeg (mark 8-5)
    origin_path = "/${var.object_prefix}"

    custom_header {
      name  = var.s3_access_header.name
      value = var.s3_access_header.value
    }
  }

  # 기본 동작: 정적 웹 -> S3 (캐싱 활성화, HTTP -> HTTPS 리다이렉트)
  default_cache_behavior {
    target_origin_id       = var.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  # /book* -> ALB (무캐싱, 쿼리 스트링/바디 전달, POST 경로 재작성)
  ordered_cache_behavior {
    path_pattern             = "/book*"
    target_origin_id         = var.alb_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.book_rewrite.arn
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

  tags = { Name = var.cloudfront_name }
}
