# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# IRSA(IAM Roles for Service Accounts) 용 Customer Managed Policy
# 실제 ServiceAccount <-> Role 매핑은 eksctl(cluster.yaml) 의
# iamserviceaccount 가 OIDC 공급자와 함께 생성한다.
# 여기서는 정책 ARN 만 정의하고 eksctl 에서 attachPolicyARNs 로 참조한다.
# ---------------------------------------------------------------------------

# 앱 Pod(wsc/wsc-sa) : POST /v1/book -> DynamoDB 쓰기 (요구사항 9.4 IRSA)
resource "aws_iam_policy" "app" {
  name = "wsc-app-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoRW"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.wsc.arn
      },
      {
        Sid      = "KmsDynamo"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.dynamodb.arn
      },
    ]
  })
}

# Fluent Bit(logging/fluent-bit) : CloudWatch Logs 전송 + KMS
resource "aws_iam_policy" "fluentbit" {
  name = "wsc-fluentbit-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.logs.arn
      },
    ]
  })
}

# ECR Pull-Through Cache: 노드 IAM Role 이 캐시 리포지터리를 생성·import 할 수 있도록
# AmazonEC2ContainerRegistryReadOnly 에는 이 두 액션이 없으므로 별도 정책으로 추가한다.
resource "aws_iam_policy" "ecr_pull_through" {
  name = "wsc-ecr-pull-through-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository"]
      Resource = "arn:aws:ecr:${var.region}:${local.account_id}:repository/*"
    }]
  })
}

# EBS CSI Driver 가 CMK 로 볼륨을 암호화할 수 있도록 추가 권한 (요구사항 9.6)
resource "aws_iam_policy" "ebs_csi_kms" {
  name = "wsc-ebs-csi-kms-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
        Resource = aws_kms_key.eks.arn
        Condition = {
          Bool = { "kms:GrantIsForAWSResource" = "true" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey",
        ]
        Resource = aws_kms_key.eks.arn
      },
    ]
  })
}
