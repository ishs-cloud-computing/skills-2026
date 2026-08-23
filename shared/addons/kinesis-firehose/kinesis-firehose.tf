# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Kinesis Data Stream → Firehose → S3 부착 스니펫 (+ Lambda ESM 옵션).
# aws_kinesis_stream 안에 넣는 하드닝 인자(KMS·retention·용량 모드)는 README "블록" 절.
# 원본: set-02 task-2 module-2-analytics terraform/kinesis.tf, module-3-msk lambda.tf
# ---------------------------------------------------------------------------

data "aws_caller_identity" "addon_firehose" {}

# ----- 적재 버킷 -----
resource "aws_s3_bucket" "addon_firehose" {
  bucket        = var.addon_firehose_bucket_name
  force_destroy = true
  tags          = { Name = var.addon_firehose_bucket_name }
}

# ----- Firehose 오류 로그 -----
resource "aws_cloudwatch_log_group" "addon_firehose" {
  name              = "/aws/kinesisfirehose/${var.addon_firehose_name}"
  retention_in_days = var.addon_firehose_log_retention_days
}

resource "aws_cloudwatch_log_stream" "addon_firehose" {
  name           = "DestinationDelivery"
  log_group_name = aws_cloudwatch_log_group.addon_firehose.name
}

# ----- 서비스 역할 (스트림 읽기 · S3 쓰기 · 로그) -----
data "aws_iam_policy_document" "addon_firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [data.aws_caller_identity.addon_firehose.account_id]
    }
  }
}

resource "aws_iam_role" "addon_firehose" {
  name               = var.addon_firehose_role_name
  assume_role_policy = data.aws_iam_policy_document.addon_firehose_assume.json
}

data "aws_iam_policy_document" "addon_firehose" {
  statement {
    sid = "ReadSourceStream"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetShardIterator",
      "kinesis:GetRecords",
      "kinesis:ListShards",
    ]
    resources = [var.addon_firehose_stream_arn]
  }

  statement {
    sid = "WriteBucket"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.addon_firehose.arn,
      "${aws_s3_bucket.addon_firehose.arn}/*",
    ]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.addon_firehose.arn}:*"]
  }

  # CMK 암호화 스트림은 Decrypt 가 없으면 레코드를 조용히 못 읽는다 (오류 로그에만 남음).
  dynamic "statement" {
    for_each = var.addon_firehose_stream_kms_key_arn == "" ? [] : [1]
    content {
      sid       = "DecryptSourceStream"
      actions   = ["kms:Decrypt"]
      resources = [var.addon_firehose_stream_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "addon_firehose" {
  name   = "${var.addon_firehose_role_name}-policy"
  role   = aws_iam_role.addon_firehose.id
  policy = data.aws_iam_policy_document.addon_firehose.json
}

# ----- Firehose: Kinesis 소스 → S3 -----
resource "aws_kinesis_firehose_delivery_stream" "addon" {
  name        = var.addon_firehose_name
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = var.addon_firehose_stream_arn
    role_arn           = aws_iam_role.addon_firehose.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.addon_firehose.arn
    bucket_arn          = aws_s3_bucket.addon_firehose.arn
    prefix              = var.addon_firehose_prefix
    error_output_prefix = var.addon_firehose_error_prefix
    buffering_size      = var.addon_firehose_buffer_mb
    buffering_interval  = var.addon_firehose_buffer_sec
    compression_format  = var.addon_firehose_compression

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.addon_firehose.name
      log_stream_name = aws_cloudwatch_log_stream.addon_firehose.name
    }
  }

  tags = { Name = var.addon_firehose_name }

  depends_on = [aws_iam_role_policy.addon_firehose]
}

# ----- Lambda ESM (Kinesis 트리거) — 기존 Lambda 에 스트림 소비 트리거 부착 -----
locals {
  addon_firehose_esm_enabled = var.addon_firehose_esm_function_name != ""
}

# 스트림 읽기 권한이 없으면 ESM 생성 자체가 "Cannot access stream" 으로 실패한다.
resource "aws_iam_role_policy_attachment" "addon_firehose_esm" {
  count      = local.addon_firehose_esm_enabled ? 1 : 0
  role       = var.addon_firehose_esm_lambda_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
}

resource "aws_lambda_event_source_mapping" "addon_kinesis" {
  count             = local.addon_firehose_esm_enabled ? 1 : 0
  event_source_arn  = var.addon_firehose_stream_arn
  function_name     = var.addon_firehose_esm_function_name
  starting_position = var.addon_firehose_esm_starting_position
  batch_size        = var.addon_firehose_esm_batch_size

  depends_on = [aws_iam_role_policy_attachment.addon_firehose_esm]
}
