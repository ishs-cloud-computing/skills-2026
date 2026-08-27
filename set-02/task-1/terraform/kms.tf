# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# KMS Customer Managed Keys
# - wskorea26-s3-key       : S3 객체 암호화 (요구사항 4, mark 2-2)
# - wskorea26-dynamodb-key : DynamoDB 테이블 암호화 (요구사항 7, mark 4-1)
# - wskorea26-eks-key      : EKS Secret Envelope 암호화 (요구사항 8, mark 5-2)
# mark 는 각 리소스의 키를 alias 로 역조회하므로 alias 이름이 정확해야 한다.
# ---------------------------------------------------------------------------

# 공통: 계정 root 전체 권한
data "aws_iam_policy_document" "kms_root" {
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

# ----- wskorea26-s3-key -----
# CloudFront(OAC)가 SSE-KMS 객체를 복호화할 수 있도록 service principal 에 Decrypt 허용.
# (배포 ARN 직접 참조 시 key->distribution->bucket->key 순환 → SourceAccount 조건으로 회피)
data "aws_iam_policy_document" "kms_s3" {
  source_policy_documents = [data.aws_iam_policy_document.kms_root.json]

  statement {
    sid       = "AllowCloudFrontDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "s3" {
  description             = "${var.kms_aliases.s3} : S3 static objects"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_s3.json
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.kms_aliases.s3}"
  target_key_id = aws_kms_key.s3.key_id
}

# ----- wskorea26-dynamodb-key -----
resource "aws_kms_key" "dynamodb" {
  description             = "${var.kms_aliases.dynamodb} : DynamoDB table"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_root.json
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.kms_aliases.dynamodb}"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# ----- wskorea26-eks-key -----
resource "aws_kms_key" "eks" {
  description             = "${var.kms_aliases.eks} : EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_root.json
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.kms_aliases.eks}"
  target_key_id = aws_kms_key.eks.key_id
}
