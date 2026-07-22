# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DynamoDB (과제지 1. NoSQL - 1/2)
# - 예약 테이블: train_id/seat_id 키, Streams NEW_AND_OLD_IMAGES, PITR, On-Demand
# - GSI gsi-user-reservations: user_id/reserved_at.
#   sparse index 는 앱(app.py)이 cancel 시 user_id/reserved_at 을 REMOVE 하는
#   방식으로 구현된다 — 키 속성이 없는 항목은 GSI 에 포함되지 않는다.
# - 감사 테이블: event_id 단일 키
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
