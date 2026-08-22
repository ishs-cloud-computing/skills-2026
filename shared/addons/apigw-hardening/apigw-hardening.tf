# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# API Gateway REST 강화 부착 스니펫 — 새 리소스만 여기. 스테이지·usage plan 블록 안에 넣는 인자
# (access_log_settings·xray_tracing_enabled·throttle_settings·quota_settings)와 model·gateway_response
# 예시는 README 블록. 원본: set-05 task-2 module-4 apigw.tf.
# ---------------------------------------------------------------------------

# 액세스 로그 목적지 — stage.access_log_settings.destination_arn 에 연결(README 블록)
resource "aws_cloudwatch_log_group" "addon_apigwhard_access" {
  name              = "/aws/apigateway/${var.addon_apigwhard_api_name}/${var.addon_apigwhard_stage_name}"
  retention_in_days = var.addon_apigwhard_log_retention_days

  tags = { Name = "${var.addon_apigwhard_api_name}-access" }
}

# 실행 로그(logging_level)·메트릭은 계정 단위 CloudWatch 역할이 없으면 apply 가 BadRequest 로 실패한다.
data "aws_iam_policy_document" "addon_apigwhard_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon_apigwhard_cw" {
  name               = "${var.addon_apigwhard_api_name}-cw-role"
  assume_role_policy = data.aws_iam_policy_document.addon_apigwhard_assume.json
}

resource "aws_iam_role_policy_attachment" "addon_apigwhard_cw" {
  role       = aws_iam_role.addon_apigwhard_cw.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# 계정당 1개 (리전별) — 다른 모듈이 이미 만들었으면 이 블록을 지운다
resource "aws_api_gateway_account" "addon_apigwhard" {
  cloudwatch_role_arn = aws_iam_role.addon_apigwhard_cw.arn

  depends_on = [aws_iam_role_policy_attachment.addon_apigwhard_cw]
}

# 스테이지 전체 메서드(*/*) 로깅·메트릭·스로틀
resource "aws_api_gateway_method_settings" "addon_apigwhard" {
  rest_api_id = var.addon_apigwhard_rest_api_id
  stage_name  = var.addon_apigwhard_stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = var.addon_apigwhard_logging_level
    data_trace_enabled     = false
    throttling_burst_limit = var.addon_apigwhard_throttle_burst
    throttling_rate_limit  = var.addon_apigwhard_throttle_rate
  }

  depends_on = [aws_api_gateway_account.addon_apigwhard]
}

# ----- CORS: OPTIONS MOCK (cors_resource_id 비우면 생성 안 함) -----
locals {
  addon_apigwhard_cors = var.addon_apigwhard_cors_resource_id != "" ? 1 : 0
}

resource "aws_api_gateway_method" "addon_apigwhard_options" {
  count = local.addon_apigwhard_cors

  rest_api_id   = var.addon_apigwhard_rest_api_id
  resource_id   = var.addon_apigwhard_cors_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "addon_apigwhard_options" {
  count = local.addon_apigwhard_cors

  rest_api_id = var.addon_apigwhard_rest_api_id
  resource_id = var.addon_apigwhard_cors_resource_id
  http_method = aws_api_gateway_method.addon_apigwhard_options[0].http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "addon_apigwhard_options" {
  count = local.addon_apigwhard_cors

  rest_api_id = var.addon_apigwhard_rest_api_id
  resource_id = var.addon_apigwhard_cors_resource_id
  http_method = aws_api_gateway_method.addon_apigwhard_options[0].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "addon_apigwhard_options" {
  count = local.addon_apigwhard_cors

  rest_api_id = var.addon_apigwhard_rest_api_id
  resource_id = var.addon_apigwhard_cors_resource_id
  http_method = aws_api_gateway_method.addon_apigwhard_options[0].http_method
  status_code = aws_api_gateway_method_response.addon_apigwhard_options[0].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.addon_apigwhard_cors_origin}'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,x-api-key'"
  }

  depends_on = [aws_api_gateway_integration.addon_apigwhard_options]
}
