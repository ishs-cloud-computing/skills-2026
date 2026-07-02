# attribute 정의는 키 스키마인 client_id 하나만 — booking_id 등 나머지 5개는 아이템 속성 (과제 9장)
resource "aws_dynamodb_table" "booking" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "client_id"

  attribute {
    name = "client_id"
    type = "S"
  }

  tags = {
    Name = local.table_name
  }
}
