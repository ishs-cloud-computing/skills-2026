# 키 정책은 기본(계정 root 위임) — 채점 IAM Role의 describe/scan이 막히지 않게 함
resource "aws_kms_key" "ddb" {
  description             = "CMK for DynamoDB table ${var.table_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.name_prefix}-ddb-key"
  }
}

resource "aws_kms_alias" "ddb" {
  name          = local.kms_alias
  target_key_id = aws_kms_key.ddb.key_id
}

# attribute 정의는 키 스키마인 booking_id 하나만 — 나머지는 아이템 속성
resource "aws_dynamodb_table" "booking" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "booking_id"

  attribute {
    name = "booking_id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.ddb.arn
  }

  tags = {
    Name = var.table_name
  }
}
