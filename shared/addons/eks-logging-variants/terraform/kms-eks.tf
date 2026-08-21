# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# EKS 플랫폼 CMK — Secret envelope · 노드 EBS · CloudWatch Logs 공용
# 원본: set-07 task-1 kms.tf(kms_platform) + cloudwatch.tf + set-05 task-1 iam.tf(ebs_csi_kms)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_ekslog" {}
data "aws_region" "addon_ekslog" {}

data "aws_iam_policy_document" "addon_ekslog_kms" {
  statement {
    sid       = "EnableRoot"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.addon_ekslog.account_id}:root"]
    }
  }

  # logs 서비스 문장이 없으면 로그 그룹 kms_key_id 가 AccessDenied
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
      identifiers = ["logs.${data.aws_region.addon_ekslog.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.addon_ekslog.region}:${data.aws_caller_identity.addon_ekslog.account_id}:log-group:*"]
    }
  }

  # 관리형 NodeGroup 의 EBS(volumeKmsKeyID) — 없으면 노드가 조용히 부팅 실패한다
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
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.addon_ekslog.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }
  statement {
    sid       = "AllowAutoScalingGrant"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.addon_ekslog.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_kms_key" "addon_ekslog" {
  description             = "EKS platform CMK: secrets envelope / node EBS / CloudWatch Logs"
  enable_key_rotation     = true
  rotation_period_in_days = var.addon_ekslog_kms_rotation_days
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.addon_ekslog_kms.json
}

resource "aws_kms_alias" "addon_ekslog" {
  name          = "alias/${var.addon_ekslog_kms_alias}"
  target_key_id = aws_kms_key.addon_ekslog.key_id
}

# Control Plane 로그 그룹 선생성 — eksctl 이 먼저 만들면 CMK 없이 생긴다
resource "aws_cloudwatch_log_group" "addon_ekslog_cluster" {
  count             = var.addon_ekslog_create_cluster_log_group ? 1 : 0
  name              = "/aws/eks/${var.addon_ekslog_cluster_name}/cluster"
  retention_in_days = var.addon_ekslog_log_retention_days
  kms_key_id        = aws_kms_key.addon_ekslog.arn

  tags = { Name = "${var.addon_ekslog_cluster_name}-cluster-log" }
}

# EBS CSI 컨트롤러가 CMK 로 PV 를 만들 때 필요 (StorageClass kmsKeyId) — SA 역할에 attach
resource "aws_iam_policy" "addon_ekslog_ebs_csi_kms" {
  name = "${var.addon_ekslog_cluster_name}-ebs-csi-kms-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
        Resource  = aws_kms_key.addon_ekslog.arn
        Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } }
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = aws_kms_key.addon_ekslog.arn
      },
    ]
  })
}

output "addon_ekslog_kms_arn" {
  value = aws_kms_key.addon_ekslog.arn
}

output "addon_ekslog_ebs_csi_kms_policy_arn" {
  value = aws_iam_policy.addon_ekslog_ebs_csi_kms.arn
}
