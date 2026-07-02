# ---------------------------------------------------------------------------
# CloudFront (요구사항 10-2)
# - unicorn-svc-cf : Origin = s3-origin(S3+OAC) + app-origin(unicorn-alb VPC Origin)
# - S3 정적 GET 응답 캐싱, ALB 요청은 캐싱 없이 QueryString 전달
# - app-origin 은 VPC Origin 으로 Internal ALB 에 인터넷 노출 없이 도달
# - WAF(unicorn-waf) 연결
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "unicorn-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "unicorn-alb-origin"
    arn                    = aws_lb.app.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

# AWS 관리형 정책
#  - CachingOptimized           : 658327ea-f89d-4fab-a63d-7e88639e58f6 (S3 정적 캐싱)
#  - CachingDisabled            : 4135ea2d-6df8-44a3-9df3-4b5a84be39ad (ALB 무캐싱)
#  - AllViewerExceptHostHeader  : b689b0a8-53d0-40ab-baf2-68738e2966ac (QueryString/쿠키/헤더 전달)
locals {
  cache_optimized               = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_caching_disabled = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  orp_all_viewer_except_host    = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = false
  comment             = "unicorn-svc-cf"
  price_class         = "PriceClass_All"
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.unicorn.arn

  # ----- s3-origin (S3 + OAC) -----
  origin {
    origin_id                = "s3-origin"
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ----- app-origin (unicorn-alb VPC Origin) -----
  origin {
    origin_id   = "app-origin"
    domain_name = aws_lb.app.dns_name

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  # 기본 동작: 정적 콘텐츠 -> s3-origin (캐싱)
  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_optimized
  }

  # API(/v1/*) -> app-origin (무캐싱, QueryString 전달)
  ordered_cache_behavior {
    path_pattern             = "/v1/*"
    target_origin_id         = "app-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_except_host
  }

  # /health -> app-origin
  ordered_cache_behavior {
    path_pattern             = "/health"
    target_origin_id         = "app-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_except_host
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "unicorn-svc-cf" }
}
