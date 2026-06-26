# ---------------------------------------------------------------------------
# DynamoDB (요구사항 6)
# - Table Name: books / Partition Key: booking_id (String)
# - GSI: client_id-index / Partition Key: client_id (String)  (채점 3-1)
# - CMK(alias/gj2026-db-key) 암호화 (채점 3-2)
# - 쓰기 권한은 book 앱(IRSA 역할)만 허용 (채점 3-3)
# 비키 속성(username/email/concert_name/created_at)은 스키마리스이므로 정의 불필요.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "books" {
  name         = "books"
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
    name            = "client_id-index"
    hash_key        = "client_id"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "books" }
}

# 리소스 기반 정책: 쓰기 액션을 book 앱 역할(gj2026-book-app-role) 외 모든 principal
# 에 대해 explicit Deny. 명시적 Deny 가 admin 의 identity 기반 Allow 도 무력화한다.
# (채점 3-3 CloudShell admin put-item → AccessDenied). 읽기(Lambda Query/GetItem)는 무관.
# aws:PrincipalArn 조건키를 사용하므로 역할이 아직 존재하지 않아도 정책 생성 가능.
data "aws_iam_policy_document" "books_resource" {
  statement {
    sid    = "DenyWritesExceptBookApp"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:BatchWriteItem",
    ]
    resources = [
      aws_dynamodb_table.books.arn,
      "${aws_dynamodb_table.books.arn}/index/*",
    ]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${local.account_id}:role/${local.book_app_role_name}",
        "arn:aws:sts::${local.account_id}:assumed-role/${local.book_app_role_name}/*",
      ]
    }
  }
}

resource "aws_dynamodb_resource_policy" "books" {
  resource_arn = aws_dynamodb_table.books.arn
  policy       = data.aws_iam_policy_document.books_resource.json
}
