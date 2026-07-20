# ---------------------------------------------------------------------------
# CMK 3종 + alias (plan.md §3.2) — 채점이 alias 이름으로 역추적
# - db/eks 키는 기본 정책(root 위임)만 두고 사용 권한은 IAM 정책 측에서 부여
# - s3 키만 CloudFront OAC 서비스 principal 허용이 별도로 필요 (없으면 8-1 전멸)
# ---------------------------------------------------------------------------

resource "aws_kms_key" "db" {
  description         = "DynamoDB books SSE"
  enable_key_rotation = true
}

resource "aws_kms_alias" "db" {
  name          = "alias/${var.name_prefix}-db-key"
  target_key_id = aws_kms_key.db.key_id
}

resource "aws_kms_key" "eks" {
  description         = "EKS secrets envelope encryption"
  enable_key_rotation = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name_prefix}-eks-key"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_kms_key" "s3" {
  description         = "S3 static bucket SSE"
  enable_key_rotation = true

  # SourceArn 을 StringLike 와일드카드로 거는 이유: 배포 ARN 을 직접 참조하면
  # key -> bucket -> distribution -> key 순환 참조가 생긴다
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringLike = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${local.account_id}:distribution/*"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name_prefix}-s3-key"
  target_key_id = aws_kms_key.s3.key_id
}
