# apigw-hardening 부착 스니펫

API Gateway REST 확장 문항(액세스 로그·X-Ray·실행 로그/메트릭/스로틀·usage plan 제한·요청 모델·
커스텀 게이트웨이 응답·CORS)을 **기존 REST API 스테이지**에 붙인다. 대응 후보: set-05 task-2 module-4-rest-api.

## RUN guard

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체를 `init`/`apply` 하지 않으므로 기존 Kit의 state를 건드리지 않는다.

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

- **VERIFY** = 이 README의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 이 README에는 이 KIT 고유 문제만 둔다.

## 파일

- `apigw-hardening.tf` — 액세스 로그 그룹, 계정 CloudWatch 역할(`aws_api_gateway_account`), `aws_api_gateway_method_settings`(`*/*`), CORS OPTIONS MOCK 세트(선택).
- `variables.tf` — `addon_apigwhard_*` 변수.
- 스테이지·usage plan 블록 **안에** 넣는 인자와 model·gateway_response 는 아래 `## 블록`.

## 부착 절차

1. 두 `.tf` 를 `set-05/task-2/module-4-rest-api/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 주입:

   ```hcl
   addon_apigwhard_api_name           = "wsc-rest-api"
   addon_apigwhard_rest_api_id        = "abc123def4"
   addon_apigwhard_stage_name         = "prod"
   addon_apigwhard_log_retention_days = 7
   addon_apigwhard_throttle_burst     = 100
   addon_apigwhard_throttle_rate      = 50
   addon_apigwhard_logging_level      = "INFO"
   addon_apigwhard_cors_resource_id   = "" # CORS 요구 시 /v1/user 리소스 ID
   addon_apigwhard_cors_origin        = "*"
   ```

   기존 리소스를 직접 참조하려면 `var.addon_apigwhard_rest_api_id` → `aws_api_gateway_rest_api.this.id`,
   `var.addon_apigwhard_stage_name` → `aws_api_gateway_stage.prod.stage_name`,
   `var.addon_apigwhard_cors_resource_id` → `aws_api_gateway_resource.user.id`.
3. 필요한 블록을 기존 `aws_api_gateway_stage`·`aws_api_gateway_usage_plan` 안에 추가한다(아래).
4. CORS 를 붙였으면 기존 `aws_api_gateway_deployment.triggers.redeployment` 목록에
   `aws_api_gateway_integration_response.addon_apigwhard_options[0].id` 를 추가한다 — 안 하면 새 메서드가 배포되지 않는다.
5. `terraform fmt` → `validate` → `plan` 으로 기존 리소스 diff 가 stage/usage plan in-place 와 deployment 교체뿐인지 확인 → `apply`.
6. 확인: `curl -i "https://<id>.execute-api.<region>.amazonaws.com/prod/v1/healthcheck"` 후 로그 그룹에 스트림 생성 확인.

## 블록

### 액세스 로그 + X-Ray (스테이지)

```hcl
# aws_api_gateway_stage 리소스 안에:
xray_tracing_enabled = true

access_log_settings {
  destination_arn = aws_cloudwatch_log_group.addon_apigwhard_access.arn
  format = jsonencode({
    requestId      = "$context.requestId"
    ip             = "$context.identity.sourceIp"
    requestTime    = "$context.requestTime"
    httpMethod     = "$context.httpMethod"
    resourcePath   = "$context.resourcePath"
    status         = "$context.status"
    responseLength = "$context.responseLength"
  })
}
```

### usage plan 스로틀·쿼터

```hcl
# aws_api_gateway_usage_plan 리소스 안에:
throttle_settings {
  burst_limit = 20
  rate_limit  = 10
}

quota_settings {
  limit  = 1000
  period = "DAY" # DAY / WEEK / MONTH
  offset = 0
}
```

### 요청 모델 (JSON Schema) + 본문 검증

```hcl
# 새 블록:
resource "aws_api_gateway_model" "addon_apigwhard" {
  rest_api_id  = var.addon_apigwhard_rest_api_id
  name         = "UserModel" # 과제지 명시 이름
  content_type = "application/json"
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "User"
    type      = "object"
    required  = ["name", "age", "country"]
    properties = {
      name    = { type = "string" }
      age     = { type = "integer", minimum = 0 }
      country = { type = "string" }
    }
  })
}

resource "aws_api_gateway_request_validator" "addon_apigwhard_body" {
  name                        = "validate-body"
  rest_api_id                 = var.addon_apigwhard_rest_api_id
  validate_request_parameters = false
  validate_request_body       = true
}
```

```hcl
# 기존 aws_api_gateway_method(POST) 리소스 안에:
request_validator_id = aws_api_gateway_request_validator.addon_apigwhard_body.id
request_models = {
  "application/json" = aws_api_gateway_model.addon_apigwhard.name
}
```

### 커스텀 게이트웨이 응답 본문

```hcl
# 새 블록 — response_type: BAD_REQUEST_BODY / BAD_REQUEST_PARAMETERS / MISSING_AUTHENTICATION_TOKEN /
#   THROTTLED / QUOTA_EXCEEDED / DEFAULT_4XX / DEFAULT_5XX ...
resource "aws_api_gateway_gateway_response" "addon_apigwhard_4xx" {
  rest_api_id   = var.addon_apigwhard_rest_api_id
  response_type = "DEFAULT_4XX"
  response_templates = {
    "application/json" = "{\"message\": \"$context.error.messageString\"}"
  }
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}
```

gateway_response 를 추가·수정했으면 deployment `triggers` 에 `.id` 를 넣어 재배포한다.

### CORS — `apigw-hardening.tf` 의 OPTIONS 세트 + 실제 응답 헤더

OPTIONS 프리플라이트는 키트가 만든다. 실제 GET/POST 응답에도 `Access-Control-Allow-Origin` 이 필요하면
Lambda proxy 응답 `headers` 에 넣는다(통합 응답 매핑은 proxy 통합에 적용되지 않는다).

## 함정

- `aws_api_gateway_account` 는 **리전당 계정 1개** 싱글턴. 같은 리전의 다른 모듈이 이미 만들었으면 이 키트의 블록을 지우거나 `terraform import aws_api_gateway_account.addon_apigwhard api-gateway-account`. `logging_level != OFF` 인 method_settings 는 이 역할 없이는 `CloudWatch Logs role ARN must be set` 로 실패.
- `access_log_settings.destination_arn` 은 로그 그룹 ARN **그대로**(`:*` 붙이면 실패). 이름을 `/aws/apigateway/` 로 시작하지 않아도 되나 콘솔 관례.
- 스테이지·usage plan·method_settings 변경은 **in-place**. 새 메서드(OPTIONS)·model·gateway_response·통합 변경은 **deployment 재생성**이 있어야 반영 — `triggers.redeployment` 에 id 추가. `create_before_destroy = true` 가 이미 있어 stage 는 끊기지 않는다.
- usage plan `throttle_settings`/`quota_settings` 는 **API Key 별** 제한, method_settings 의 throttling 은 스테이지 전체 제한. 과제지가 어느 쪽인지 읽는다.
- 요청 모델의 `name` 과 gateway_response 의 응답 본문 문자열은 채점 스크립트가 그대로 비교할 수 있다(set-05 m4 mark `{"message": "Missing required request parameters: [age]"}`). 공백·따옴표까지 일치.
- `data_trace_enabled = true` 는 요청/응답 전문을 로그에 남긴다 — 시크릿 노출 감점 가능, 기본 false.
- CORS OPTIONS 는 `api_key_required = false`·`authorization = NONE` 이어야 브라우저 프리플라이트가 통과한다.
- X-Ray 는 `xray_tracing_enabled` 만으로 켜진다(Lambda 쪽 `tracing_config` 는 별도 — lambda-hardening 키트). 추가 IAM 불필요.

## 실전 구현 (참고용)

- `set-05/task-2/module-4-rest-api/terraform/apigw.tf` — REST API·validator·model·gateway_response·deployment triggers·usage plan
- `set-05/task-2/module-4-rest-api/terraform/lambda.tf` — proxy 통합 Lambda
