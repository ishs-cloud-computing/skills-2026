# ---------------------------------------------------------------------------
# IRSA 용 Customer Managed Policy
# ServiceAccount <-> Role 매핑은 eksctl(cluster.yaml) 의 iamserviceaccount 가
# OIDC 공급자와 함께 생성한다. 여기서는 정책만 정의하고 eksctl 이 attachPolicyARNs
# 로 참조한다. book 앱 역할 이름은 DynamoDB 리소스 정책(쓰기 제한)에서도 참조하므로
# eksctl 에서 roleName 으로 고정한다.
# ---------------------------------------------------------------------------

locals {
  book_app_role_name = "gj2026-book-app-role"
}

# book 앱 Pod(skills/book-sa): DynamoDB 읽기/쓰기 + KMS (요구사항 4·6)
resource "aws_iam_policy" "book_app" {
  name = "gj2026-book-app-policy"
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
          "dynamodb:BatchWriteItem",
        ]
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*",
        ]
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

# Fluent Bit(logging/aws-for-fluent-bit): CloudWatch Logs 전송 (요구사항 14)
resource "aws_iam_policy" "fluentbit" {
  name = "gj2026-fluentbit-policy"
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
    ]
  })
}

# Grafana(monitoring/grafana): CloudWatch 데이터소스 조회 (요구사항 14)
resource "aws_iam_policy" "grafana_cw" {
  name = "gj2026-grafana-cloudwatch-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetInsightRuleReport",
          "tag:GetResources",
        ]
        Resource = "*"
      },
    ]
  })
}

# ECR Pull-Through Cache: 노드가 캐시 리포지터리를 생성·import 할 수 있도록 추가
resource "aws_iam_policy" "ecr_pull_through" {
  name = "gj2026-ecr-pull-through-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository"]
      Resource = "arn:aws:ecr:${var.region}:${local.account_id}:repository/*"
    }]
  })
}

# EBS CSI Driver 가 CMK 로 볼륨을 암호화할 수 있도록 추가 권한 (요구사항 7 EBS 암호화)
resource "aws_iam_policy" "ebs_csi_kms" {
  name = "gj2026-ebs-csi-kms-policy"
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
