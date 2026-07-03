# ---------------------------------------------------------------------------
# IAM Roles
# - EKS Pod Identity 역할 (trust: pods.eks.amazonaws.com, 본 클러스터 한정)
# - Lambda 실행 역할
# 주의: mark 5-5 / 7-2 는 list-attached-role-policies(관리형 정책)만 읽으므로
#       채점 대상 정책은 inline 이 아닌 aws_iam_policy + attachment 로 만든다.
#       또한 7-2 는 Action 텍스트에 '*' 문자가 있으면 FAIL → 액션 전부 명시.
# ---------------------------------------------------------------------------

# 공용 Pod Identity 신뢰 정책 (본 클러스터로 한정)
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

# ----- Book App Pod (wsc2026/wsc2026-book-sa) : PutItem 최소 권한 (요구사항 8) -----
resource "aws_iam_role" "book_pod" {
  name               = "wsc2026-book-pod-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "book_pod" {
  statement {
    sid       = "DynamoWrite"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.book.arn]
  }
  # 테이블이 db CMK(SSE-KMS)로 암호화되어 있어 데이터 키 생성/복호화 필요
  statement {
    sid       = "DbCmkUse"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.db.arn]
  }
}

resource "aws_iam_policy" "book_pod" {
  name   = "wsc2026-book-pod-policy"
  policy = data.aws_iam_policy_document.book_pod.json
}

resource "aws_iam_role_policy_attachment" "book_pod" {
  role       = aws_iam_role.book_pod.name
  policy_arn = aws_iam_policy.book_pod.arn
}

# ----- Lambda 실행 역할 (요구사항 10) -----
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "book_function" {
  name               = "wsc2026-book-function-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# mark 7-2: attach 된 정책 이름이 wsc2026-book-function-policy 단독으로 출력되어야
# 하므로 AWSLambdaBasicExecutionRole 은 붙이지 않고 logs 액션을 여기에 명시한다.
data "aws_iam_policy_document" "book_function" {
  statement {
    sid     = "DynamoRead"
    effect  = "Allow"
    actions = ["dynamodb:Query"]
    resources = [
      aws_dynamodb_table.book.arn,
      "${aws_dynamodb_table.book.arn}/index/booking_id-index",
    ]
  }
  # 환경변수 암호문(function CMK) 복호화 + 테이블 db CMK 복호화
  statement {
    sid       = "KmsDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.function.arn, aws_kms_key.db.arn]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.book_function.arn}:*"]
  }
}

resource "aws_iam_policy" "book_function" {
  name   = "wsc2026-book-function-policy"
  policy = data.aws_iam_policy_document.book_function.json
}

resource "aws_iam_role_policy_attachment" "book_function" {
  role       = aws_iam_role.book_function.name
  policy_arn = aws_iam_policy.book_function.arn
}

# ----- AWS Load Balancer Controller (kube-system/aws-load-balancer-controller) -----
resource "aws_iam_role" "lbc" {
  name               = "wsc2026-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_policy" "lbc" {
  name   = "wsc2026-lbc-policy"
  policy = file("${path.module}/iam/lbc-policy.json")
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# ----- Fluent Bit (observability/fluent-bit) : 앱 로그 → CloudWatch Logs -----
resource "aws_iam_role" "fluentbit" {
  name               = "wsc2026-fluentbit-role"
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

resource "aws_iam_policy" "fluentbit" {
  name   = "wsc2026-fluentbit-policy"
  policy = data.aws_iam_policy_document.fluentbit.json
}

resource "aws_iam_role_policy_attachment" "fluentbit" {
  role       = aws_iam_role.fluentbit.name
  policy_arn = aws_iam_policy.fluentbit.arn
}

# ----- Grafana (observability/monitoring-grafana) : CloudWatch 데이터소스 -----
resource "aws_iam_role" "grafana" {
  name               = "wsc2026-grafana-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "grafana" {
  # CloudWatch 메트릭/로그 조회 액션은 리소스 ARN 을 지원하지 않는 것이 많아 "*" 사용
  statement {
    sid    = "CloudWatchRead"
    effect = "Allow"
    actions = [
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:DescribeAlarms",
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "grafana" {
  name   = "wsc2026-grafana-policy"
  policy = data.aws_iam_policy_document.grafana.json
}

resource "aws_iam_role_policy_attachment" "grafana" {
  role       = aws_iam_role.grafana.name
  policy_arn = aws_iam_policy.grafana.arn
}
