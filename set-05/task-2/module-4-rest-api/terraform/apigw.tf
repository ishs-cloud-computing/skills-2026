# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# API Gateway REST API (과제지 6. API Gateway 구성)
# - wsc-rest-api / stage prod
# - /v1/user (POST, GET)   : Lambda Proxy 통합, API Key 필수, 요청 Validation
# - /v1/healthcheck (GET)  : MOCK 통합 -> {"status":"ok"} (Lambda 미사용, API Key 불필요)
# - API Key 없는 호출 -> 403 {"message":"Forbidden"} (기본 Gateway Response)
# - 잘못된 Query String -> 400 {"message": "Missing required request parameters: [age]"}
#   (BAD_REQUEST_PARAMETERS Gateway Response, Lambda 까지 전달되지 않음)
# ---------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "this" {
  name = var.api_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ----- /v1, /v1/user, /v1/healthcheck -----
resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "user" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "user"
}

resource "aws_api_gateway_resource" "healthcheck" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "healthcheck"
}

# ----- Request Validator / Model -----
resource "aws_api_gateway_request_validator" "params" {
  name                        = "validate-params"
  rest_api_id                 = aws_api_gateway_rest_api.this.id
  validate_request_parameters = true
  validate_request_body       = false
}

resource "aws_api_gateway_request_validator" "body" {
  name                        = "validate-body"
  rest_api_id                 = aws_api_gateway_rest_api.this.id
  validate_request_parameters = false
  validate_request_body       = true
}

resource "aws_api_gateway_model" "user" {
  rest_api_id  = aws_api_gateway_rest_api.this.id
  name         = "UserModel"
  content_type = "application/json"
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "User"
    type      = "object"
    required  = ["name", "age", "country"]
    properties = {
      name    = { type = "string" }
      age     = { type = "integer" }
      country = { type = "string" }
    }
  })
}

# ===== POST /v1/user (Lambda Proxy, API Key, Body 검증) =====
resource "aws_api_gateway_method" "user_post" {
  rest_api_id          = aws_api_gateway_rest_api.this.id
  resource_id          = aws_api_gateway_resource.user.id
  http_method          = "POST"
  authorization        = "NONE"
  api_key_required     = true
  request_validator_id = aws_api_gateway_request_validator.body.id
  request_models = {
    "application/json" = aws_api_gateway_model.user.name
  }
}

resource "aws_api_gateway_integration" "user_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.user.id
  http_method             = aws_api_gateway_method.user_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.this.invoke_arn
}

# ===== GET /v1/user (Lambda Proxy, API Key, Query 검증) =====
resource "aws_api_gateway_method" "user_get" {
  rest_api_id          = aws_api_gateway_rest_api.this.id
  resource_id          = aws_api_gateway_resource.user.id
  http_method          = "GET"
  authorization        = "NONE"
  api_key_required     = true
  request_validator_id = aws_api_gateway_request_validator.params.id
  request_parameters = {
    "method.request.querystring.name" = true
    "method.request.querystring.age"  = true
  }
}

resource "aws_api_gateway_integration" "user_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.user.id
  http_method             = aws_api_gateway_method.user_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.this.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# ===== GET /v1/healthcheck (MOCK) =====
resource "aws_api_gateway_method" "healthcheck_get" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.healthcheck.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "healthcheck" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.healthcheck.id
  http_method = aws_api_gateway_method.healthcheck_get.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "healthcheck_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.healthcheck.id
  http_method = aws_api_gateway_method.healthcheck_get.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "healthcheck_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.healthcheck.id
  http_method = aws_api_gateway_method.healthcheck_get.http_method
  status_code = aws_api_gateway_method_response.healthcheck_200.status_code
  response_templates = {
    "application/json" = "{\"status\":\"ok\"}"
  }
  depends_on = [aws_api_gateway_integration.healthcheck]
}

# ----- 잘못된 Query String 응답을 과제 표기와 정확히 일치시킴 -----
resource "aws_api_gateway_gateway_response" "bad_params" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "BAD_REQUEST_PARAMETERS"
  status_code   = "400"
  response_templates = {
    "application/json" = "{\"message\": \"$context.error.messageString\"}"
  }
}

# ----- Deployment + Stage prod -----
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.v1.id,
      aws_api_gateway_resource.user.id,
      aws_api_gateway_resource.healthcheck.id,
      aws_api_gateway_method.user_post.id,
      aws_api_gateway_integration.user_post.id,
      aws_api_gateway_method.user_get.id,
      aws_api_gateway_integration.user_get.id,
      aws_api_gateway_method.healthcheck_get.id,
      aws_api_gateway_integration.healthcheck.id,
      aws_api_gateway_integration_response.healthcheck_200.id,
      aws_api_gateway_gateway_response.bad_params.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name
}

# ----- API Key + Usage Plan -----
resource "aws_api_gateway_api_key" "this" {
  name    = var.api_key_name
  enabled = true
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "wsc-rest-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "this" {
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}
