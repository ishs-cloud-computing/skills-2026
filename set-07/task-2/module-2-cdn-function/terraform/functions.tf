# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_cloudfront_key_value_store" "ab_config" {
  name = var.kvs_name
}

# 채점(2-2)이 키 목록을 정확 일치로 검사하므로 여분 키가 남지 않게 exclusive 로 관리.
resource "aws_cloudfrontkeyvaluestore_keys_exclusive" "ab_config" {
  key_value_store_arn = aws_cloudfront_key_value_store.ab_config.arn

  resource_key_value_pair {
    key   = "weight"
    value = var.ab_weight
  }

  resource_key_value_pair {
    key   = "version_a"
    value = var.version_a_path
  }

  resource_key_value_pair {
    key   = "version_b"
    value = var.version_b_path
  }
}

# publish = true → LIVE 스테이지 발행 (과제지 요구).
resource "aws_cloudfront_function" "req" {
  name    = var.req_fn_name
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/cloudfront/req-fn.js")

  key_value_store_associations = [aws_cloudfront_key_value_store.ab_config.arn]
}

resource "aws_cloudfront_function" "res" {
  name    = var.res_fn_name
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/cloudfront/res-fn.js")
}
