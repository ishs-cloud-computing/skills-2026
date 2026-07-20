# ---------------------------------------------------------------------------
# DynamoDB (plan.md §3.4)
# - GSI projection INCLUDE: 8-4 응답 필드를 GSI 단독 Query 로 완성
# - 리소스 기반 정책: book 앱 역할 외 전원 쓰기 Deny (채점 3-3)
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "books" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "booking_id"

  attribute {
    name = "booking_id"
    type = "S"
  }

  attribute {
    name = "client_id"
    type = "S"
  }

  global_secondary_index {
    name               = var.gsi_name
    hash_key           = "client_id"
    projection_type    = "INCLUDE"
    non_key_attributes = ["username", "email", "concert_name"]
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.db.arn
  }
}

# Deny 활성 상태에서는 관리자도 아이템 삭제 불가 —
# 데이터 정리 시 enable_ddb_write_deny=false 로 일시 해제 (런북 7단계)
resource "aws_dynamodb_resource_policy" "write_deny" {
  count = var.enable_ddb_write_deny ? 1 : 0

  resource_arn = aws_dynamodb_table.books.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyWritesExceptBookApp"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = aws_dynamodb_table.books.arn
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-book-app-role",
              "arn:aws:sts::${local.account_id}:assumed-role/${var.name_prefix}-book-app-role/*",
            ]
          }
        }
      },
    ]
  })
}
