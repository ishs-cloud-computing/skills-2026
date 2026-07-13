# DynamoDB (과제지 6. DynamoDB — mark 4-1: 키 스키마 sensorId/timestamp)
# 과제지의 속성 표(studentId 등)는 module-1 복붙 오류 — 키 스키마가 채점 기준
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
