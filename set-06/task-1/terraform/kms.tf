# ---------------------------------------------------------------------------
# KMS Customer Managed Keys
# 채점 대상 alias (정확 일치):
#   alias/gj2026-db-key  (DynamoDB, 채점 3-2)
#   alias/gj2026-eks-key (EKS Secret + EBS, 채점 4-1)
#   alias/gj2026-s3-key  (S3, 채점 6-2)
# ECR/CloudWatch Logs 키는 alias 채점이 없어 용도별 alias 만 부여한다.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_default" {
  statement {
    sid       = "EnableRoot"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

# CloudWatch Logs 서비스가 사용할 수 있도록 허용하는 키 정책
data "aws_iam_policy_document" "kms_logs" {
  source_policy_documents = [data.aws_iam_policy_document.kms_default.json]

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${local.account_id}:log-group:*"]
    }
  }
}

# Managed Node Group 의 EBS 볼륨 암호화 시 Auto Scaling 서비스 연결 역할이
# 키를 사용할 수 있어야 한다(없으면 ASG 가 인스턴스를 기동하지 못함).
data "aws_iam_policy_document" "kms_eks" {
  source_policy_documents = [data.aws_iam_policy_document.kms_default.json]

  statement {
    sid    = "AllowAutoScalingServiceRole"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }

  statement {
    sid       = "AllowAutoScalingGrants"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_kms_key" "s3" {
  description             = "gj2026 S3 SSE-KMS"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
resource "aws_kms_alias" "s3" {
  name          = "alias/gj2026-s3-key"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "ecr" {
  description             = "gj2026 ECR encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
resource "aws_kms_alias" "ecr" {
  name          = "alias/gj2026-ecr-key"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_kms_key" "dynamodb" {
  description             = "gj2026 DynamoDB CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
resource "aws_kms_alias" "dynamodb" {
  name          = "alias/gj2026-db-key"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# EKS Secret Envelope Encryption + EBS 볼륨 암호화 공용
resource "aws_kms_key" "eks" {
  description             = "gj2026 EKS secrets & EBS volume CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_eks.json
}
resource "aws_kms_alias" "eks" {
  name          = "alias/gj2026-eks-key"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_kms_key" "logs" {
  description             = "gj2026 CloudWatch Logs CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_logs.json
}
resource "aws_kms_alias" "logs" {
  name          = "alias/gj2026-logs-key"
  target_key_id = aws_kms_key.logs.key_id
}
