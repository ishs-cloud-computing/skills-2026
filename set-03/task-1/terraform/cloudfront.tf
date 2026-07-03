# ---------------------------------------------------------------------------
# CloudFront (요구사항 13) — 2차 apply (enable_cdn=true)
# - wsc2026-cdn (Name 태그 — mark 9-1 이 태그로 검색)
# - Origin 3개:
#     s3-origin     : 정적 페이지 (OAC, origin_path=/static, 캐싱 O)
#     alb-origin    : /booking → wsc2026-app-alb (캐싱 X)
#                     ALB 는 LBC 생성물이라 data 소스로 이름 조회 → 2차 apply 필요
#     lambda-origin : /v1/book → Lambda Function URL (OAC, 캐싱 X)
# - /booking 은 CloudFront Function 으로 앱 실제 경로 /v1/book 으로 rewrite
#   (앱은 POST /v1/book 만 제공하고 ALB 는 경로 rewrite 불가)
# - WAF(wsc2026-waf) 연결
# ---------------------------------------------------------------------------

data "aws_lb" "app" {
  count = var.enable_cdn ? 1 : 0
  name  = "wsc2026-app-alb"
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "wsc2026-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = "wsc2026-lambda-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "booking_rewrite" {
  name    = "wsc2026-booking-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite /booking to app path /v1/book"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      request.uri = '/v1/book';
      return request;
    }
  EOT
}

# AWS 관리형 정책
#  - CachingOptimized          : 658327ea-f89d-4fab-a63d-7e88639e58f6 (S3 캐싱 활성)
#  - CachingDisabled           : 4135ea2d-6df8-44a3-9df3-4b5a84be39ad (ALB/Lambda 캐싱 비활성)
#  - AllViewerExceptHostHeader : b689b0a8-53d0-40ab-baf2-68738e2966ac (QueryString/바디 전달)
locals {
  cache_optimized            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_disabled             = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  orp_all_viewer_except_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

  # https://<id>.lambda-url.<region>.on.aws/ → 호스트만 추출
  lambda_origin_domain = trimsuffix(trimprefix(aws_lambda_function_url.book_get.function_url, "https://"), "/")
}

resource "aws_cloudfront_distribution" "cdn" {
  count = var.enable_cdn ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = false
  comment             = "wsc2026-cdn"
  price_class         = "PriceClass_All"
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.wsc2026.arn

  # ----- s3-origin : 정적 페이지 (루트 접근 시 static/index.html) -----
  origin {
    origin_id                = "s3-origin"
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_path              = "/static"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ----- alb-origin : Book 애플리케이션 POST API -----
  origin {
    origin_id   = "alb-origin"
    domain_name = data.aws_lb.app[0].dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ----- lambda-origin : 데이터 조회 GET API (Function URL + OAC) -----
  origin {
    origin_id                = "lambda-origin"
    domain_name              = local.lambda_origin_domain
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 기본 동작: 정적 페이지 → s3-origin (캐싱 활성)
  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_optimized
  }

  # POST /booking → alb-origin (무캐싱, /v1/book 으로 rewrite)
  ordered_cache_behavior {
    path_pattern             = "/booking"
    target_origin_id         = "alb-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_disabled
    origin_request_policy_id = local.orp_all_viewer_except_host

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.booking_rewrite.arn
    }
  }

  # GET /v1/book → lambda-origin (무캐싱, QueryString 전달)
  ordered_cache_behavior {
    path_pattern             = "/v1/book*"
    target_origin_id         = "lambda-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_disabled
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

  tags = { Name = "wsc2026-cdn" }
}
