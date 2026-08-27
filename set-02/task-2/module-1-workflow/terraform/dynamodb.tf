# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DynamoDB (과제지 2. DynamoDB, mark 1-2)
# - PK studentId (HASH) + SK examDate (RANGE), KeySchema 정확 일치 채점
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "score" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "studentId"
  range_key    = "examDate"

  attribute {
    name = "studentId"
    type = "S"
  }

  attribute {
    name = "examDate"
    type = "S"
  }

  tags = { Name = var.table_name }
}
