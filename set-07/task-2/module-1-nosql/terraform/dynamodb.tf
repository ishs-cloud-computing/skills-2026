# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DynamoDB (과제지 1. NoSQL - 1/2)
# GSI 키를 user_id/reserved_at 로 두는 것은 제공 app.py 가 cancel 시 이 두 속성을 REMOVE 하는
# 것과 한 쌍이다 — 키 속성이 없는 항목은 GSI 에 포함되지 않아 sparse index 가 된다.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "reservation" {
  name         = var.reservation_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "train_id"
  range_key    = "seat_id"

  attribute {
    name = "train_id"
    type = "S"
  }

  attribute {
    name = "seat_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "reserved_at"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }

  global_secondary_index {
    name            = var.gsi_name
    hash_key        = "user_id"
    range_key       = "reserved_at"
    projection_type = "ALL"
  }

  tags = { Name = var.reservation_table_name }
}

resource "aws_dynamodb_table" "audit" {
  name         = var.audit_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = { Name = var.audit_table_name }
}
