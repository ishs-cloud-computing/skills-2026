# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# KMS Customer Managed Keys (요구사항 4)
# - unicorn-kms-app      : Secrets Manager, DynamoDB
# - unicorn-kms-data     : S3, ECR
# - unicorn-kms-platform : EKS Envelope, EBS, Log, WAF 로그
#                          → WAF 로그는 us-east-1 이므로 다중 리전 키(MRK)로 구성.
# - 모든 키 90일 자동 회전.
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

# ----- unicorn-kms-app : DynamoDB / Secrets Manager -----
resource "aws_kms_key" "app" {
  description             = "unicorn-kms-app : DynamoDB / Secrets Manager"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_root.json
}
resource "aws_kms_alias" "app" {
  name          = "alias/unicorn-kms-app"
  target_key_id = aws_kms_key.app.key_id
}

# ----- unicorn-kms-data : S3 / ECR -----
# CloudFront(OAC) 가 SSE-KMS 객체를 복호화할 수 있도록 service principal 에 Decrypt 허용.
# (배포 ARN 직접 참조 시 key->distribution->bucket->key 순환 → SourceAccount 조건으로 회피)
data "aws_iam_policy_document" "kms_data" {
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

resource "aws_kms_key" "data" {
  description             = "unicorn-kms-data : S3 / ECR"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_data.json
}
resource "aws_kms_alias" "data" {
  name          = "alias/unicorn-kms-data"
  target_key_id = aws_kms_key.data.key_id
}

# ----- unicorn-kms-platform : MRK (primary in ap-northeast-2) -----
# EKS secret envelope, 노드 EBS, 모든 CloudWatch Logs(양 리전), WAF 로그 암호화에 공용.
data "aws_iam_policy_document" "kms_platform" {
  source_policy_documents = [data.aws_iam_policy_document.kms_root.json]

  # CloudWatch Logs (ap-northeast-2 + us-east-1) 서비스가 로그 그룹을 암호화
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
      type = "Service"
      identifiers = [
        "logs.${var.region}.amazonaws.com",
        "logs.us-east-1.amazonaws.com",
      ]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:${var.region}:${local.account_id}:log-group:*",
        "arn:aws:logs:us-east-1:${local.account_id}:log-group:*",
      ]
    }
  }

  # 관리형 NodeGroup 의 EBS 볼륨 암호화 (AutoScaling 서비스 연결 역할)
  statement {
    sid    = "AllowAutoScalingUse"
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
    sid       = "AllowAutoScalingGrant"
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

# 프라이머리(ap-northeast-2, 다중 리전) — EKS/EBS/Log(서울)에서 사용.
# 선수 유의사항 7(모든 리소스는 서울)에 따라 프라이머리를 서울에 둔다. us-east-1 은 MRK 레플리카로 커버.
resource "aws_kms_key" "platform" {
  description             = "unicorn-kms-platform : EKS/EBS/Log (MRK primary)"
  multi_region            = true
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_platform.json
}
resource "aws_kms_alias" "platform" {
  name          = "alias/unicorn-kms-platform"
  target_key_id = aws_kms_key.platform.key_id
}

# 레플리카(us-east-1) — WAF 로그 암호화. 회전은 프라이머리가 관리(AWS 가 레플리카로 복사).
resource "aws_kms_replica_key" "platform_use1" {
  provider                = aws.use1
  description             = "unicorn-kms-platform : WAF Log (MRK replica, us-east-1)"
  primary_key_arn         = aws_kms_key.platform.arn
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_platform.json
}
resource "aws_kms_alias" "platform_use1" {
  provider      = aws.use1
  name          = "alias/unicorn-kms-platform"
  target_key_id = aws_kms_replica_key.platform_use1.key_id
}
