# ---------------------------------------------------------------------------
# KMS Customer Managed Keys (요구사항 5·6·7·9·10)
# - wsc2026-db-kms       : DynamoDB SSE
# - wsc2026-ecr-kms      : ECR 이미지 암호화
# - wsc2026-eks-kms      : EKS secrets envelope 암호화
# - wsc2026-bucket-kms   : S3 SSE-KMS (+ CloudFront OAC 복호화)
# - wsc2026-function-kms : Lambda 코드/환경변수 암호화
#
# 유의사항 10: 키 정책에 root principal 과 "kms:*" 액션 금지 (mark check_kms 가
# 정책 텍스트를 grep). 대신 배포자 신원(aws_iam_session_context)을 키 관리자로
# 명시하고 액션을 나열한다. kms:Put* 이 있어 lockout safety check 를 통과한다.
# 주의: eksctl/docker push/kubectl 을 다른 신원으로 실행하면 키 사용이 거부되므로
# 모든 작업은 terraform 과 같은 자격증명으로 수행한다 (README 참고).
# ---------------------------------------------------------------------------

locals {
  # 관리 + 사용 액션 명시 나열 ("kms:*" 문자열 없이 전체 권한과 동등)
  kms_admin_actions = [
    "kms:Create*",
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Put*",
    "kms:Update*",
    "kms:Revoke*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
    "kms:RotateKeyOnDemand",
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:CreateGrant",
    "kms:RetireGrant",
  ]
}

# 공통: 배포자 관리자 statement (root 대체)
data "aws_iam_policy_document" "kms_admin" {
  statement {
    sid       = "KeyAdministration"
    effect    = "Allow"
    actions   = local.kms_admin_actions
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = local.kms_admin_arns
    }
  }
}

# ----- wsc2026-db-kms : DynamoDB SSE -----
# 테이블 사용 주체(EKS Pod / Lambda)가 SSE 데이터 키를 다룰 수 있어야 한다.
# root 위임이 없으므로 키 정책에 사용 주체를 직접 명시한다.
data "aws_iam_policy_document" "kms_db" {
  source_policy_documents = [data.aws_iam_policy_document.kms_admin.json]

  statement {
    sid    = "AllowTableConsumers"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.book_pod.arn,
        aws_iam_role.book_function.arn,
      ]
    }
  }
}

resource "aws_kms_key" "db" {
  description             = "${var.name_prefix}-db-kms : DynamoDB SSE"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_db.json
}
resource "aws_kms_alias" "db" {
  name          = "alias/${var.name_prefix}-db-kms"
  target_key_id = aws_kms_key.db.key_id
}

# ----- wsc2026-ecr-kms : ECR -----
# 리포지토리 생성 시 배포자의 CreateGrant 로 ECR 서비스에 위임되므로 admin 만으로 충분.
resource "aws_kms_key" "ecr" {
  description             = "${var.name_prefix}-ecr-kms : ECR image encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_admin.json
}
resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.name_prefix}-ecr-kms"
  target_key_id = aws_kms_key.ecr.key_id
}

# ----- wsc2026-eks-kms : EKS secrets envelope -----
# eksctl(=배포자 신원)이 CreateCluster 시 CreateGrant/DescribeKey 를 호출한다.
resource "aws_kms_key" "eks" {
  description             = "${var.name_prefix}-eks-kms : EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_admin.json
}
resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name_prefix}-eks-kms"
  target_key_id = aws_kms_key.eks.key_id
}

# ----- wsc2026-bucket-kms : S3 SSE-KMS -----
# CloudFront(OAC) 가 SSE-KMS 객체를 복호화할 수 있도록 service principal 허용.
# (배포 ARN 직접 참조 시 key→distribution→bucket→key 순환 → SourceAccount 조건으로 회피)
data "aws_iam_policy_document" "kms_bucket" {
  source_policy_documents = [data.aws_iam_policy_document.kms_admin.json]

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

resource "aws_kms_key" "bucket" {
  description             = "${var.name_prefix}-bucket-kms : S3 static hosting SSE-KMS"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_bucket.json
}
resource "aws_kms_alias" "bucket" {
  name          = "alias/${var.name_prefix}-bucket-kms"
  target_key_id = aws_kms_key.bucket.key_id
}

# ----- wsc2026-function-kms : Lambda -----
# 환경변수 전송 중 암호화(암호문 env)를 실행 역할이 런타임에 복호화한다 (요구사항 10).
data "aws_iam_policy_document" "kms_function" {
  source_policy_documents = [data.aws_iam_policy_document.kms_admin.json]

  statement {
    sid       = "AllowLambdaExecutionRoleDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.book_function.arn]
    }
  }
}

resource "aws_kms_key" "function" {
  description             = "${var.name_prefix}-function-kms : Lambda code/env encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_function.json
}
resource "aws_kms_alias" "function" {
  name          = "alias/${var.name_prefix}-function-kms"
  target_key_id = aws_kms_key.function.key_id
}
