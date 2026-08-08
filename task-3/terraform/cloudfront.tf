# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 단일 엔드포인트: CloudFront
#   기본 동작        → internet-facing ALB   : /v1/* API + 미지정 경로(Ingress 404)
#   /images/*        → S3(OAC)               : 정적 이미지 캐싱
# wait_for_deployment=false로 배포 완료를 기다리지 않고 도메인을 즉시 확보한다.

# ALB는 AWS Load Balancer Controller가 k8s/20-ingress.yaml로부터 만든다.
# 따라서 이 데이터 소스는 Ingress가 ALB를 프로비저닝한 뒤에만 읽을 수 있다 —
# README의 STEP 순서(Ingress apply → 전체 terraform apply)가 이 제약에서 나온다.
data "aws_lb" "this" {
  name = local.alb_name
}

# k8s/20-ingress.yaml의 security-group-prefix-lists 주석 해제 시 쓰는 값.
# (ALB를 CloudFront에서만 접근 가능하게 잠그는 선택 사항 — 과제 필수는 아니다)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# /images/<key> → S3 오브젝트 키는 루트(<key>)이므로 prefix를 벗겨야 한다.
# origin_path는 붙이기만 가능하고 제거는 불가 → CloudFront Function이 유일한 방법.
resource "aws_cloudfront_function" "strip_images" {
  name    = "skills-strip-images"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      request.uri = request.uri.substring(7); // "/images/a.jpg" -> "/a.jpg"
      return request;
    }
  EOT
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "skills-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  # AWS 관리형 정책 ID
  cache_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  cache_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  orp_all_viewer_no_host  = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "skills-cdn"
  is_ipv6_enabled     = false
  price_class         = "PriceClass_All"
  web_acl_id          = aws_wafv2_web_acl.this.arn
  wait_for_deployment = false

  origin {
    origin_id   = "alb"
    domain_name = data.aws_lb.this.dns_name

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

  # API + 미지정 경로: 캐싱 없음, 쿼리스트링/헤더 전부 오리진 전달
  # (응답이 요청 uuid를 echo하므로 캐시하면 변조가 된다)
  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_no_host
  }

  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = "s3-images"
    viewer_protocol_policy = "redirect-to-https"
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

  tags = { Name = "skills-cdn" }
}
