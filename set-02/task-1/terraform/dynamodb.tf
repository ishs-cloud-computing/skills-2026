# ---------------------------------------------------------------------------
# DynamoDB (요구사항 7)
# - wskorea26-data-table : PK client_id(S), 삭제방지, wskorea26-dynamodb-key 암호화 (mark 4-1)
# - GSI concert_name-created_at-index : Lambda 가 콘서트별 예매를 "데이터베이스 레벨"
#   최신순으로 조회하기 위한 인덱스 (Reference03 — Query + ScanIndexForward=false)
# 비키 속성(username/email/booking_id)은 스키마리스이므로 정의 불필요.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "data" {
  name                        = var.table_name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "client_id"
  deletion_protection_enabled = true

  attribute {
    name = "client_id"
    type = "S"
  }
  attribute {
    name = "concert_name"
    type = "S"
  }
  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "concert_name-created_at-index"
    hash_key        = "concert_name"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = var.table_name }
}
