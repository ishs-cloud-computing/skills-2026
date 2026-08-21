# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# IAM Roles
# - EKS Pod Identity 역할 (trust: pods.eks.amazonaws.com, AssumeRole + TagSession,
#   본 클러스터(SourceArn) 한정). eksctl 의 podIdentityAssociations 가 roleARN 으로 참조.
# - unicorn-audit-role (요구사항 11)
# ---------------------------------------------------------------------------

# 공용 Pod Identity 신뢰 정책 (본 클러스터로 한정 — 요구사항 8 Security)
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.cluster_arn]
    }
  }
}

# ----- Book App (unicorn/unicorn-book-app-sa) : POST -> DynamoDB PutItem (최소 권한) -----
resource "aws_iam_role" "book_app" {
  name               = "unicorn-book-app-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "book_app" {
  statement {
    sid       = "DynamoWrite"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.concert.arn]
  }
  # 테이블이 App CMK(SSE-KMS)로 암호화되어 있어 PutItem 시 데이터 키 생성/복호화 필요
  statement {
    sid       = "AppCmkUse"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.app.arn]
  }
}

resource "aws_iam_role_policy" "book_app" {
  name   = "unicorn-book-app-policy"
  role   = aws_iam_role.book_app.id
  policy = data.aws_iam_policy_document.book_app.json
}

# ----- Fluent Bit (logging/fluent-bit) : CloudWatch Logs 전송 -----
resource "aws_iam_role" "fluentbit" {
  name               = "unicorn-fluentbit-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "fluentbit" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.book_app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "fluentbit" {
  name   = "unicorn-fluentbit-policy"
  role   = aws_iam_role.fluentbit.id
  policy = data.aws_iam_policy_document.fluentbit.json
}

# ----- CloudWatch Exporter (monitoring/cloudwatch-exporter) : ALB 메트릭 조회 -----
resource "aws_iam_role" "cwexporter" {
  name               = "unicorn-cwexporter-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "cwexporter" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "tag:GetResources",
    ]
    resources = ["*"] # CloudWatch 조회 액션은 리소스 ARN 미지원
  }
}

resource "aws_iam_role_policy" "cwexporter" {
  name   = "unicorn-cwexporter-policy"
  role   = aws_iam_role.cwexporter.id
  policy = data.aws_iam_policy_document.cwexporter.json
}

# ----- AWS Load Balancer Controller (kube-system/aws-load-balancer-controller) -----
resource "aws_iam_role" "lbc" {
  name               = "unicorn-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_policy" "lbc" {
  name   = "unicorn-lbc-policy"
  policy = file("${path.module}/iam/lbc-policy.json")
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# ----- EBS CSI Driver (kube-system/ebs-csi-controller-sa) : 표준 정책 + Platform CMK -----
resource "aws_iam_role" "ebs_csi" {
  name               = "unicorn-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_managed" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "aws_iam_policy_document" "ebs_csi_kms" {
  statement {
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = [aws_kms_key.platform.arn]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
      "kms:GenerateDataKey*", "kms:DescribeKey",
    ]
    resources = [aws_kms_key.platform.arn]
  }
}

resource "aws_iam_role_policy" "ebs_csi_kms" {
  name   = "unicorn-ebs-csi-kms-policy"
  role   = aws_iam_role.ebs_csi.id
  policy = data.aws_iam_policy_document.ebs_csi_kms.json
}

# ---------------------------------------------------------------------------
# Audit Role (요구사항 11)
# - 동일 계정 IAM Principal 이 External ID 와 함께 Assume 했을 때만 사용 가능
# - 최대 세션 1시간, DynamoDB 조회 + VPC/EKS Describe (액션 와일드카드 금지)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "audit_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.audit_external_id]
    }
  }
}

resource "aws_iam_role" "audit" {
  name                 = "unicorn-audit-role"
  assume_role_policy   = data.aws_iam_policy_document.audit_trust.json
  max_session_duration = 3600
}

locals {
  # GSI 이름은 dynamodb.tf 의 "do not change" 블록이 정본이다. 리터럴을 복사하면
  # 드리프트가 나므로 리소스에서 직접 읽는다(GSI 는 1개 — one() 이 그 전제를 강제한다).
  audit_table_resources = [
    aws_dynamodb_table.concert.arn,
    "${aws_dynamodb_table.concert.arn}/index/${one(aws_dynamodb_table.concert.global_secondary_index).name}",
  ]
}

data "aws_iam_policy_document" "audit" {
  # 요구사항 11 은 액션뿐 아니라 리소스 와일드카드도 금지한다. GSI 가
  # client-id-created-at-index 하나뿐이라 "/index/*" 대신 그 ARN 을 직접 쓴다.
  # statement 를 액션 1개씩 쪼갠 이유: aws_iam_policy_document 는 statement 순서는
  # 보존하지만 statement 안의 actions 는 재정렬한다. 1개면 순서가 확정돼
  # mark.md:604 예상 출력(dynamodb:GetItem dynamodb:Query ...)과 그대로 일치한다.
  statement {
    sid       = "DynamoGetItem"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem"]
    resources = local.audit_table_resources
  }
  statement {
    sid       = "DynamoQuery"
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = local.audit_table_resources
  }
  # 테이블이 App CMK(SSE-KMS)로 암호화되어 있어 GetItem/Query 시 복호화 필요
  statement {
    sid       = "AppCmkDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.app.arn]
  }
  # ec2:DescribeVpcs 는 리소스 레벨 권한을 지원하지 않아(Service Authorization Reference 의
  # 리소스 타입 열이 비어 있다) Resource="*" 외 선택지가 없다. 요구사항 11 의 리소스 와일드카드
  # 금지에 유일하게 걸리는 지점이며 이의신청 근거가 된다.
  statement {
    sid       = "DescribeVpc"
    effect    = "Allow"
    actions   = ["ec2:DescribeVpcs"]
    resources = ["*"]
  }
  # eks:DescribeCluster 는 cluster 를 필수 리소스 타입으로 가지므로 본 클러스터로 한정한다.
  # (요구사항 11 "8번 EKS Cluster 에 대한 Describe 액션으로 한정")
  statement {
    sid       = "DescribeCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [local.cluster_arn]
  }
}

resource "aws_iam_role_policy" "audit" {
  name   = "unicorn-audit-policy"
  role   = aws_iam_role.audit.id
  policy = data.aws_iam_policy_document.audit.json
}
