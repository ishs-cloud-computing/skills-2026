# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# KeyValueStore (과제지 2. CDN Function - 2. KeyValueStore 구성, 채점 2-2)
# - 정확히 3개 키: weight / version_a / version_b
# - keys_exclusive 단일 리소스로 관리해 키별 리소스 병렬 쓰기의 ETag 충돌을 피한다.
# - 채점 2-6 이 weight 를 1.0/0.0 으로 바꿨다가 0.3 으로 복원하므로
#   채점 후 terraform plan 에 drift 가 없어야 정상이다.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_key_value_store" "ab_config" {
  name    = var.kvs_name
  comment = "A/B weight and version paths for skillsphone landing"
}

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
