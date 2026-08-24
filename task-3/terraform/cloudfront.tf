# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ALB는 AWS Load Balancer Controller가 k8s/20-ingress.yaml로부터 만든다. 이 데이터 소스는
# Ingress가 ALB를 띄운 뒤에만 읽히며, README의 STEP 순서가 이 제약에서 나온다.
# ALB가 이미 지워진 뒤 destroy 하면 이 조회가 plan 자체를 막는다. -var alb_exists=false 로 끈다.
data "aws_lb" "this" {
  count = var.alb_exists ? 1 : 0
  name  = local.alb_name
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# origin_path는 prefix를 붙이기만 가능하고 제거는 불가라 /images 를 벗기는 방법이 Function뿐이다.
resource "aws_cloudfront_function" "strip_images" {
  name    = local.cdn_function_name
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      // "/images/" 까지만 오면 uri 가 "/" 가 되어 버킷 루트 ListObjects 로 나간다.
      // s3.tf 가 CloudFront 에 s3:ListBucket 을 줬으므로 그대로 두면 목록이 200 으로 새어 나온다.
      if (request.uri.length <= 8) {
        return {
          statusCode: 404,
          statusDescription: 'Not Found',
          body: { encoding: 'text', data: '{"error":"Not Found"}' }
        };
      }
      request.uri = request.uri.substring(7); // "/images/a.jpg" -> "/a.jpg"
      return request;
    }
  EOT
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = local.cdn_oac_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  cache_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  cache_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  orp_all_viewer_no_host  = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = local.cdn_name
  is_ipv6_enabled     = false
  price_class         = "PriceClass_All"
  web_acl_id          = aws_wafv2_web_acl.this.arn
  wait_for_deployment = false

  origin {
    origin_id = "alb"
    # alb_exists=false 는 destroy 전용이라 이 대체값은 실제로 배포되지 않는다.
    domain_name = try(data.aws_lb.this[0].dns_name, "alb-already-deleted.invalid")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "s3-images"
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # 응답이 요청 uuid를 echo하므로 캐시하면 변조가 된다.
  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "allow-all"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_no_host
  }

  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = "s3-images"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_caching_optimized

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.strip_images.arn
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

  tags = { Name = local.cdn_name }
}
