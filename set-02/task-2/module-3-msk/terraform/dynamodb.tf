# DynamoDB (과제지 6. DynamoDB — mark 3-1: 키 스키마 sensorId/timestamp)
# 속성 타입(humidity Number, 그 외 String)은 sensor_consumer 가 넣는다 — 키만 여기서 선언
resource "aws_dynamodb_table" "sensor_data" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sensorId"
  range_key    = "timestamp"

  attribute {
    name = "sensorId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}
