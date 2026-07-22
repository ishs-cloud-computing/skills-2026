# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudFront Functions (과제지 2. CDN Function - 3, 채점 2-2)
# - 둘 다 cloudfront-js-2.0, publish=true → LIVE 스테이지 발행
# - viewer-request 함수만 KVS 연결 (weight/version 경로 조회)
# ---------------------------------------------------------------------------

resource "aws_cloudfront_function" "request" {
  name    = var.req_fn_name
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "A/B assign + URI rewrite from KVS"
  code    = file("${path.module}/func/ab-request.js")

  key_value_store_associations = [aws_cloudfront_key_value_store.ab_config.arn]
}

resource "aws_cloudfront_function" "response" {
  name    = var.res_fn_name
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Set x-sp-ab cookie on fresh assignment"
  code    = file("${path.module}/func/ab-response.js")
}
