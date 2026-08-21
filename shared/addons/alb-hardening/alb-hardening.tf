# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# ALB 보강: 액세스 로그 버킷 + 버킷 정책, 오리진 검증 헤더 규칙, HTTPS 리스너(ACM 있을 때만).
# 기존 aws_lb 안에 넣는 access_logs / enable_deletion_protection / drop_invalid_header_fields 는 README 블록.
# 원본: set-02/set-08 task-1 alb.tf (헤더 규칙), provider 문서 aws_elb_service_account (로그 정책)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_albh" {}

# 2022-08 이전 리전(ap-northeast-2·us-east-1 등)은 리전별 ELB 계정 ID 가 principal.
# 이후 신규 리전(ap-southeast-3 등)은 이 data source 가 없어 에러 — 그땐 이 data 와 첫 statement 를 지우고
# logdelivery.elasticloadbalancing.amazonaws.com statement 만 남긴다.
data "aws_elb_service_account" "addon_albh" {}

locals {
  addon_albh_log_bucket = "${var.addon_albh_log_bucket_prefix}-${data.aws_caller_identity.addon_albh.account_id}"
  addon_albh_log_path   = var.addon_albh_log_prefix == "" ? "AWSLogs/${data.aws_caller_identity.addon_albh.account_id}/*" : "${var.addon_albh_log_prefix}/AWSLogs/${data.aws_caller_identity.addon_albh.account_id}/*"
}

resource "aws_s3_bucket" "addon_alb_logs" {
  bucket        = local.addon_albh_log_bucket
  force_destroy = true

  tags = { Name = local.addon_albh_log_bucket }
}

resource "aws_s3_bucket_public_access_block" "addon_alb_logs" {
  bucket                  = aws_s3_bucket.addon_alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ALB 로그 버킷은 SSE-S3 만 지원 — SSE-KMS 로 바꾸면 로그가 조용히 안 쌓인다.
resource "aws_s3_bucket_server_side_encryption_configuration" "addon_alb_logs" {
  bucket = aws_s3_bucket.addon_alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "addon_alb_logs" {
  statement {
    sid       = "AllowELBAccountPutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.addon_alb_logs.arn}/${local.addon_albh_log_path}"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.addon_albh.arn]
    }
  }

  statement {
    sid       = "AllowLogDeliveryServicePutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.addon_alb_logs.arn}/${local.addon_albh_log_path}"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "addon_alb_logs" {
  bucket = aws_s3_bucket.addon_alb_logs.id
  policy = data.aws_iam_policy_document.addon_alb_logs.json

  depends_on = [aws_s3_bucket_public_access_block.addon_alb_logs]
}

# ----- 오리진 검증 헤더 규칙 (CloudFront custom_header 와 짝) -----
# 리스너 default_action 은 403 fixed-response 여야 의미가 있다 (README 블록).
resource "aws_lb_listener_rule" "addon_origin_verify" {
  count = var.addon_albh_listener_arn != "" ? 1 : 0

  listener_arn = var.addon_albh_listener_arn
  priority     = var.addon_albh_rule_priority

  action {
    type             = "forward"
    target_group_arn = var.addon_albh_target_group_arn
  }

  condition {
    http_header {
      http_header_name = var.addon_albh_header_name
      values           = [var.addon_albh_header_value]
    }
  }
}

# ----- HTTPS 리스너 (ACM 인증서가 있을 때만) -----
resource "aws_lb_listener" "addon_https" {
  count = var.addon_albh_certificate_arn != "" ? 1 : 0

  load_balancer_arn = var.addon_albh_alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.addon_albh_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = var.addon_albh_target_group_arn
  }
}
