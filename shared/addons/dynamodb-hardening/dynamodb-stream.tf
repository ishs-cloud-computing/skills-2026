# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DynamoDB Streams → 기존 Lambda 부착 스니펫
# 원본: set-07 task-2 module-1 lambda.tf (스트림 읽기 정책 + ESM)
# 전제: 테이블에 stream_enabled/stream_view_type 가 켜져 있어야 한다 (README 블록).
# ---------------------------------------------------------------------------

# ESM 생성 시 Lambda 가 이 권한이 없으면 "Cannot access stream" 으로 생성 자체가 실패한다.
data "aws_iam_policy_document" "addon_ddb_stream" {
  statement {
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
    ]
    resources = [var.addon_ddb_stream_arn]
  }

  statement {
    actions   = ["dynamodb:ListStreams"]
    resources = ["${split("/stream/", var.addon_ddb_stream_arn)[0]}/stream/*"]
  }
}

resource "aws_iam_role_policy" "addon_ddb_stream" {
  name   = "${var.addon_ddb_lambda_function_name}-ddb-stream"
  role   = var.addon_ddb_lambda_role_name
  policy = data.aws_iam_policy_document.addon_ddb_stream.json
}

# on_failure 목적지를 쓰면 Lambda Role 에 그 큐/토픽 sqs:SendMessage / sns:Publish 도 필요하다.
resource "aws_lambda_event_source_mapping" "addon_ddb" {
  event_source_arn  = var.addon_ddb_stream_arn
  function_name     = var.addon_ddb_lambda_function_name
  starting_position = "LATEST"

  batch_size                     = var.addon_ddb_esm_batch_size
  maximum_retry_attempts         = var.addon_ddb_esm_max_retry_attempts
  bisect_batch_on_function_error = var.addon_ddb_esm_bisect_on_error

  dynamic "destination_config" {
    for_each = var.addon_ddb_esm_on_failure_arn == "" ? [] : [1]
    content {
      on_failure {
        destination_arn = var.addon_ddb_esm_on_failure_arn
      }
    }
  }

  depends_on = [aws_iam_role_policy.addon_ddb_stream]
}
