# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DynamoDB (과제지 6. DynamoDB 구성)
# - Table: wsc-rest-table, Partition Key: name (String)
# - PAY_PER_REQUEST(On-Demand): 3000 RPS 이상 Burst 트래픽에 자동 대응
#   (name 을 PK 로 사용하면 사용자별로 키가 분산되어 Hot Partition 위험이 낮다)
# - Conditional Write 로 동일 사용자 중복 저장 방지 (lambda/index.py)
# 비키 속성(age/country)은 스키마리스이므로 attribute 정의 불필요.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "name"

  attribute {
    name = "name"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = var.table_name }
}
