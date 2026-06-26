# ---------------------------------------------------------------------------
# CloudFront (요구사항 12)
# - gj2026-cdn : Origin = S3(OAC) + 내부 ALB(VPC Origin) + Lambda(Function URL)
# - 기본: S3 정적 콘텐츠(캐싱) + 확장자 없으면 index.html rewrite(CloudFront Function)
# - /v1/*, /grafana* : 내부 ALB(VPC Origin), 캐싱 없음, QueryString 전부 전달
# - /reservation*    : Lambda Function URL, 캐싱 없음, QueryString 전달
# - HTTP -> HTTPS 리다이렉트, IPv6 off, WAF(gj2026-waf-acl) 연결
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "gj2026-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 내부 ALB 를 가리키는 VPC Origin (요구사항 12: VPC Origin Name gj2026-alb-origin)
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "gj2026-alb-origin"
    arn                    = aws_lb.this.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

locals {
  # AWS 관리형 정책
  cache_caching_optimized    = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  cache_caching_disabled     = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
  orp_all_viewer_except_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

  # Lambda Function URL 호스트(스킴/끝슬래시 제거)
  lambda_origin_host = trimsuffix(trimprefix(aws_lambda_function_url.reservation.function_url, "https://"), "/")
}

resource "aws_cloudfront_function" "rewrite" {
  name    = "gj2026-rewrite-index"
  runtime = "cloudfront-js-2.0"
  code    = file("${path.module}/cloudfront_function.js")
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = false
  comment         = "gj2026-cdn"
  price_class     = "PriceClass_All"
  web_acl_id      = aws_wafv2_web_acl.cdn.arn

  # ----- S3 Origin (정적 콘텐츠, 버킷 루트) -----
  origin {
    origin_id                = "s3-static"
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ----- ALB(VPC Origin) -----
  origin {
    origin_id   = "alb"
    domain_name = aws_lb.this.dns_name

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  # ----- Lambda Function URL (custom origin) -----
  origin {
    origin_id   = "lambda-reservation"
    domain_name = local.lambda_origin_host

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 기본: S3 정적 콘텐츠 (캐싱) + 확장자 없으면 index.html rewrite
  default_cache_behavior {
    target_origin_id       = "s3-static"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_caching_optimized

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }
  }

  # /v1/* -> ALB (book 앱, 캐싱 없음, QueryString 전달)
  ordered_cache_behavior {
    path_pattern             = "/v1/*"
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_except_host
  }

  # /grafana* -> ALB (Grafana, 캐싱 없음)
  ordered_cache_behavior {
    path_pattern             = "/grafana*"
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_except_host
  }

  # /reservation* -> Lambda Function URL (캐싱 없음, QueryString 전달)
  ordered_cache_behavior {
    path_pattern             = "/reservation*"
    target_origin_id         = "lambda-reservation"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_caching_disabled
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

  tags = { Name = "gj2026-cdn" }
}
