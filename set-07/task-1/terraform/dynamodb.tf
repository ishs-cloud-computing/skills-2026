# ---------------------------------------------------------------------------
# DynamoDB (요구사항 6)
# - unicorn-concert-db : PAY_PER_REQUEST, PK booking_id
# - GSI client-id-created-at-index : PK client_id / SK created_at / ALL
# - App CMK SSE, PITR, 삭제 방지
# 비키 속성(username/email/concert_name)은 스키마리스이므로 정의 불필요.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "concert" {
  name                        = "unicorn-concert-db"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "booking_id"
  deletion_protection_enabled = true

  attribute {
    name = "booking_id"
    type = "S"
  }
  attribute {
    name = "client_id"
    type = "S"
  }
  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "client-id-created-at-index"
    hash_key        = "client_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.app.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "unicorn-concert-db" }
}
