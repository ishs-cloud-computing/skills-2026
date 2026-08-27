# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# IAM Managed Policies (IRSA 용)
# 역할과 ServiceAccount 는 eksctl(iam.withOIDC + iam.serviceAccounts)이 생성하고,
# 여기서는 attachPolicyARNs 로 참조할 정책만 만든다.
# * Pod Identity 를 쓰지 않는 이유: eks-pod-identity-agent 가 kube-system DaemonSet
#   으로 전 노드(app 포함)에 떠서 mark 5-4(kube-system 파드는 모두 addon 노드) 를
#   위반한다. IRSA 는 노드 상주 컴포넌트가 없다.
# ---------------------------------------------------------------------------

# ----- Book App (wskorea26/wskorea26-book-sa) : DynamoDB PutItem 최소 권한 -----
data "aws_iam_policy_document" "book_app" {
  statement {
    sid       = "DynamoWrite"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.data.arn]
  }
  # 테이블이 wskorea26-dynamodb-key(SSE-KMS)로 암호화되어 있어 PutItem 시 키 사용 필요
  statement {
    sid       = "TableCmkUse"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.dynamodb.arn]
  }
}

resource "aws_iam_policy" "book_app" {
  name   = "wskorea26-book-app-policy"
  policy = data.aws_iam_policy_document.book_app.json
}

# ----- AWS Load Balancer Controller (kube-system/aws-load-balancer-controller) -----
# TargetGroupBinding 등록/해제에 사용. 정책 원본: kubernetes-sigs LBC 공식
# iam_policy.json (버전은 iam/lbc-policy.version 참고)
resource "aws_iam_policy" "lbc" {
  name   = "wskorea26-lbc-policy"
  policy = file("${path.module}/iam/lbc-policy.json")
}

# ----- Fluent Bit (monitoring/fluent-bit) : Pod 로그 -> CloudWatch Logs -----
data "aws_iam_policy_document" "fluent_bit" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.pod_logs.arn}:*"]
  }
}

resource "aws_iam_policy" "fluent_bit" {
  name   = "wskorea26-fluent-bit-policy"
  policy = data.aws_iam_policy_document.fluent_bit.json
}
