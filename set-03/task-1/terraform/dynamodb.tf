# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DynamoDB (요구사항 5)
# - wsc2026-book-table : PAY_PER_REQUEST, PK client_id, GSI booking_id-index
# - db CMK SSE, PITR 최장(35일), 삭제 방지
# - 테이블 수준 리소스 정책으로 최소 권한: Pod → PutItem, Lambda → Query
# 비키 속성(username/email/concert_name/created_at)은 스키마리스이므로 정의 불필요.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "book" {
  name                        = var.table_name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "client_id"
  deletion_protection_enabled = true

  attribute {
    name = "client_id"
    type = "S"
  }
  attribute {
    name = "booking_id"
    type = "S"
  }

  # booking_id 를 이용한 효율적 조회 (Lambda GET)
  global_secondary_index {
    name            = "booking_id-index"
    hash_key        = "booking_id"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.db.arn
  }

  point_in_time_recovery {
    enabled                 = true
    recovery_period_in_days = 35 # 최장 복구 기간 (mark 2-1: 35)
  }

  tags = { Name = var.table_name }
}

# 테이블 수준 최소 권한 (mark 2-1 이 statement 를
# "<Action> : <Principal 마지막 세그먼트>" 로 출력하므로 Action/Principal 은
# 배열이 아닌 단일 문자열로 유지한다)
resource "aws_dynamodb_resource_policy" "book" {
  resource_arn = aws_dynamodb_table.book.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPodPutItem"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.book_pod.arn }
        Action    = "dynamodb:PutItem"
        Resource  = aws_dynamodb_table.book.arn
      },
      {
        Sid       = "AllowFunctionQuery"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.book_function.arn }
        Action    = "dynamodb:Query"
        Resource = [
          aws_dynamodb_table.book.arn,
          "${aws_dynamodb_table.book.arn}/index/booking_id-index",
        ]
      },
    ]
  })
}