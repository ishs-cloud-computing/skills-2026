# ---------------------------------------------------------------------------
# CloudFront (plan.md §3.9) — 단일 엔드포인트, Origin 3개 / Behavior 4개
# - Default: S3(OAC) + viewer-request Function (캐시 키 통일 → 8-1 Hit)
# - /v1/book*, /grafana*: VPC Origin(internal ALB)
# - /reservation*: Lambda Function URL(OAC)
# ---------------------------------------------------------------------------

locals {
  # AWS Managed 캐시/오리진 요청 정책 고정 ID (plan.md §3.9 표)
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  origin_req_all_viewer_no_host  = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

  s3_origin_id     = "s3-static"
  alb_origin_id    = "alb-vpc-origin"
  lambda_origin_id = "lambda-reservation"

  # Function URL 은 https://<id>.lambda-url.<region>.on.aws/ 형태 — 도메인만 추출
  lambda_url_domain = replace(replace(aws_lambda_function_url.reservation.function_url, "https://", ""), "/", "")
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.name_prefix}-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = "${var.name_prefix}-lambda-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# internal ALB 를 인터넷 노출 없이 오리진으로 — IGW 는 attach 만 필요, 라우트 불필요(1-2 안전)
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "${var.name_prefix}-alb-origin"
    arn                    = aws_lb.main.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

# 확장자 없는 URI → /index.html 재작성 (viewer-request 는 캐시 조회 전에 실행되어
# 캐시 키가 통일된다 → 8-1 세 번째 요청 Hit). 기본 behavior 에만 연결 —
# ALB/Lambda behavior 에 붙이면 /reservation 이 재작성되어 깨진다 (plan.md §3.9)
resource "aws_cloudfront_function" "rewrite_index" {
  name    = "${var.name_prefix}-rewrite-index"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var req = event.request;
      var uri = req.uri;
      if (uri.endsWith('/')) { req.uri = uri + 'index.html'; }
      else if (!uri.split('/').pop().includes('.')) { req.uri = '/index.html'; }
      return req;
    }
  EOT
}

resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  comment         = "${var.name_prefix}-cdn"
  web_acl_id      = aws_wafv2_web_acl.main.arn
  price_class     = "PriceClass_All"
  is_ipv6_enabled = false

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    origin_id   = local.alb_origin_id
    domain_name = aws_lb.main.dns_name

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  origin {
    origin_id                = local.lambda_origin_id
    domain_name              = local.lambda_url_domain
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_policy_caching_optimized
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_index.arn
    }
  }

  # AllViewerExceptHostHeader 가 쿼리스트링을 오리진에 전달 — 누락 시 9-2 전멸
  ordered_cache_behavior {
    path_pattern             = "/v1/book*"
    target_origin_id         = local.alb_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.origin_req_all_viewer_no_host
  }

  ordered_cache_behavior {
    path_pattern             = "/grafana*"
    target_origin_id         = local.alb_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.origin_req_all_viewer_no_host
  }

  ordered_cache_behavior {
    path_pattern             = "/reservation*"
    target_origin_id         = local.lambda_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.origin_req_all_viewer_no_host
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${var.name_prefix}-cdn" }
}
