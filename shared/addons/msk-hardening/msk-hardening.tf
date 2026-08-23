# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# MSK 하드닝 부착 스니펫 — 새 리소스만 (로그 그룹·configuration·Lambda ESM).
# aws_msk_cluster 안에 넣는 인자(logging_info·open_monitoring·enhanced_monitoring·
# configuration_info·encryption_at_rest)는 README "블록" 절.
# 원본: set-02 task-2 module-3-msk terraform/msk.tf·lambda.tf·iam.tf
# ---------------------------------------------------------------------------

# ----- 브로커 로그 대상 로그 그룹 -----
resource "aws_cloudwatch_log_group" "addon_msk_broker" {
  name              = var.addon_msk_log_group_name
  retention_in_days = var.addon_msk_log_retention_days
}

# ----- server.properties configuration -----
# 클러스터에는 configuration_info { arn, revision } 로 연결한다 (README 블록). in-place 갱신.
resource "aws_msk_configuration" "addon" {
  name              = var.addon_msk_configuration_name
  kafka_versions    = var.addon_msk_kafka_versions
  server_properties = var.addon_msk_server_properties
}

# ----- Lambda ESM (MSK 트리거) — 기존 Lambda 에 토픽 소비 트리거 부착 -----
locals {
  addon_msk_esm_enabled   = var.addon_msk_esm_function_name != ""
  addon_msk_topic_prefix  = replace(var.addon_msk_cluster_arn, ":cluster/", ":topic/")
  addon_msk_group_prefix  = replace(var.addon_msk_cluster_arn, ":cluster/", ":group/")
  addon_msk_esm_topic_arn = [for t in var.addon_msk_esm_topics : "${local.addon_msk_topic_prefix}/${t}"]
}

# ESM 폴러 권한 (kafka:DescribeCluster*/GetBootstrapBrokers + ENI). 없으면 ESM 이 PROBLEM 상태로 멈춘다.
resource "aws_iam_role_policy_attachment" "addon_msk_esm" {
  count      = local.addon_msk_esm_enabled ? 1 : 0
  role       = var.addon_msk_esm_lambda_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole"
}

# IAM 인증 클러스터에서 ESM 이 함수 실행 역할로 접속하므로 kafka-cluster 데이터 액션이 필수.
data "aws_iam_policy_document" "addon_msk_esm" {
  count = local.addon_msk_esm_enabled ? 1 : 0

  statement {
    sid       = "ConnectCluster"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
    resources = [var.addon_msk_cluster_arn]
  }
  statement {
    sid       = "ConsumeTopics"
    actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = local.addon_msk_esm_topic_arn
  }
  statement {
    sid       = "ConsumerGroups"
    actions   = ["kafka-cluster:DescribeGroup", "kafka-cluster:AlterGroup"]
    resources = ["${local.addon_msk_group_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "addon_msk_esm" {
  count  = local.addon_msk_esm_enabled ? 1 : 0
  name   = "${var.addon_msk_esm_function_name}-msk-consume"
  role   = var.addon_msk_esm_lambda_role_name
  policy = data.aws_iam_policy_document.addon_msk_esm[0].json
}

resource "aws_lambda_event_source_mapping" "addon_msk" {
  count             = local.addon_msk_esm_enabled ? 1 : 0
  event_source_arn  = var.addon_msk_cluster_arn
  function_name     = var.addon_msk_esm_function_name
  topics            = var.addon_msk_esm_topics
  starting_position = "LATEST"
  batch_size        = var.addon_msk_esm_batch_size

  depends_on = [
    aws_iam_role_policy_attachment.addon_msk_esm,
    aws_iam_role_policy.addon_msk_esm,
  ]
}
