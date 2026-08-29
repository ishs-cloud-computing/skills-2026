# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# IAM (NOTES.md §3.2/§3.6/§3.8/§3.11)
# - IRSA 역할은 eksctl(iam.serviceAccounts, roleName 지정)이 생성한다 —
#   OIDC provider 가 클러스터 생성 후에야 존재하므로, Terraform 은 "정책"만 만들고
#   eksctl 이 attachPolicyARNs 로 역할에 연결한다 (배포 순서 문제 해소)
# - Lambda 실행 역할만 k8s 무관이라 Terraform 이 직접 생성
# ---------------------------------------------------------------------------

# ----- Lambda 실행 역할 -----
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "reservation-read"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoRead"
        Effect = "Allow"
        Action = ["dynamodb:Scan", "dynamodb:Query"]
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*",
        ]
      },
      {
        Sid      = "KmsDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.db.arn
      },
      {
        # EMF 는 logs:PutLogEvents 만으로 동작 (cloudwatch:PutMetricData 불필요)
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:*"
      },
    ]
  })
}

# ----- book 앱 (IRSA: skills/book-sa -> gj2026-book-app-role) -----
resource "aws_iam_policy" "book_app" {
  name = "${var.name_prefix}-book-app-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoWrite"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.books.arn
      },
      {
        Sid      = "KmsForSse"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.db.arn
      },
    ]
  })
}

# ----- Grafana (IRSA: monitoring/grafana -> gj2026-grafana-role) -----
resource "aws_iam_policy" "grafana" {
  name = "${var.name_prefix}-grafana-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:DescribeAlarms",
          "tag:GetResources",
          "ec2:DescribeRegions",
        ]
        Resource = "*"
      },
    ]
  })
}

# ----- Fluent Bit (IRSA: logging/aws-for-fluent-bit -> gj2026-fluentbit-role) -----
resource "aws_iam_policy" "fluentbit" {
  name = "${var.name_prefix}-fluentbit-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 채점이 로그 그룹 삭제 후 재생성을 기대하므로 CreateLogGroup 필수 (NOTES.md §3.11)
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:*"
      },
    ]
  })
}

# ----- AWS Load Balancer Controller (IRSA: kube-system/aws-load-balancer-controller) -----
# TargetGroupBinding 전용 축소 정책 — Ingress 를 쓰지 않으므로 생성 계열 권한 불필요
resource "aws_iam_policy" "lbc" {
  name = "${var.name_prefix}-lbc-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeNetworkInterfaces",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "RegisterTargets"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
        ]
        Resource = "arn:aws:elasticloadbalancing:*:${local.account_id}:targetgroup/*"
      },
      {
        # backend SG 규칙 자동 관리 경로 (충돌 시 --enable-backend-security-group=false)
        Sid    = "SgManage"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
        ]
        Resource = "*"
      },
    ]
  })
}

# ----- 노드 role 추가 정책: pull-through cache 최초 import (NOTES.md 함정 22) -----
resource "aws_iam_policy" "node_ptc" {
  name = "${var.name_prefix}-node-ptc-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PullThroughCacheImport"
        Effect = "Allow"
        Action = [
          "ecr:BatchImportUpstreamImage",
          "ecr:CreateRepository",
        ]
        Resource = "arn:aws:ecr:${var.region}:${local.account_id}:repository/ecr-public/*"
      },
    ]
  })
}
