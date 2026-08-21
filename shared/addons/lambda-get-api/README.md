# lambda-get-api 부착 스니펫

1과제 옵션 "Lambda GET API": DynamoDB 조회 Lambda(쿼리스트링 필수값 400·없으면 404 JSON·응답 필드 순서 고정)
+ 노출 방식 (a) ALB → Lambda / (b) Function URL + CloudFront / (c) API Gateway REST.
대응 후보: set-08/09 task-1 신규 Lambda 문항, 기존 Lambda 세트(set-02/03/05/07)의 추가 쿼리 API.

## 파일

- `lambda-get-api.tf` — 함수·최소권한 역할·선생성 로그 그룹. 테이블 이름/ARN 은 변수.
- `alb-lambda.tf` — (a) Lambda TG + permission + attachment + 리스너 규칙(GET+경로+선택 헤더). `addon_lamget_alb_listener_arn` 비우면 전부 생성 안 함.
- `lambda/index.py` — 핸들러. `KEY_NAME`·`INDEX_NAME`·`FIELDS` 환경변수로 세트별 차이 흡수.
- `variables.tf` — `addon_lamget_*` 변수.
- (b)(c) 는 아래 `## 블록`.

## 부착 절차

1. `.tf` 3개를 `set-XX/task-1/terraform/` 으로, `lambda/index.py` 를 `set-XX/task-1/terraform/lambda/` 로 복사한다.
   기존 세트에 이미 `lambda/index.py` 가 있으면 `lambda-get/index.py` 로 두고 `data "archive_file"` 의 `source_file` 을 맞춘다.
2. `terraform.tfvars` 에 주입:

   ```hcl
   addon_lamget_function_name  = "unicorn-get-booking-func"
   addon_lamget_runtime        = "python3.13"
   addon_lamget_table_name     = "unicorn-concert-table"
   addon_lamget_table_arn      = "arn:aws:dynamodb:ap-northeast-2:123456789012:table/unicorn-concert-table"
   addon_lamget_key_name       = "booking_id"
   addon_lamget_index_name     = ""  # GSI 조회면 "booking_id-index"
   addon_lamget_fields         = ["booking_id", "client_id", "username", "email", "concert_name", "created_at"]
   addon_lamget_table_kms_key_arn = "" # 테이블 CMK 면 ARN

   # (a) ALB 노출 시
   addon_lamget_alb_listener_arn  = "arn:aws:elasticloadbalancing:...:listener/app/unicorn-alb/.../..."
   addon_lamget_alb_rule_priority = 30
   addon_lamget_alb_path          = "/v1/book"
   addon_lamget_alb_header_name   = "" # 기존 규칙이 origin-verify 헤더를 검사하면 "X-Origin-Verify"
   addon_lamget_alb_header_value  = ""
   ```

   기존 리소스를 직접 참조하려면 `var.addon_lamget_table_arn` 을 `aws_dynamodb_table.<기존>.arn`,
   `var.addon_lamget_alb_listener_arn` 을 `aws_lb_listener.<기존>.arn` 으로 바꾼다.
3. `terraform fmt` → `validate` → `plan` 으로 기존 리소스 diff 없음 확인 → `apply`.
4. 확인: `curl "http://<ALB DNS>/v1/book?booking_id=B001"` (internal ALB 면 bastion/CloudShell VPC 에서), 누락 → 400, 없는 값 → 404.

## 블록

### (a) ALB → Lambda — `alb-lambda.tf` 가 전부. 규칙 priority 정합

기존 리스너 규칙을 먼저 본다(`aws_lb_listener_rule` 의 `priority`). 숫자가 낮을수록 먼저 평가된다.

| 기존 패턴 | 새 규칙 위치 |
| --- | --- |
| set-07: default → Lambda, 10 `/health`, 20 POST | 이미 default 가 Lambda. 추가 경로만 필요하면 priority 30 에 GET+경로 |
| set-05: default 404, 10 `/health` 403, 20 GET `/v1/book`, 21 POST | 기존 20 과 경로가 겹치지 않게 새 경로 + priority 30 |
| origin-verify 헤더 규칙(헤더 불일치 → 403) 이 있는 세트 | 새 규칙에도 `addon_lamget_alb_header_name/value` 로 같은 헤더 조건을 단다. 안 달면 헤더 없는 직접 호출이 Lambda 로 새어 나간다 |

### (b) Function URL + CloudFront origin/behavior

```hcl
# 새 블록 (lambda-get-api.tf 끝에):
resource "aws_lambda_function_url" "addon_lamget" {
  function_name      = aws_lambda_function.addon_lamget.function_name
  authorization_type = "AWS_IAM" # CloudFront OAC(SigV4) 로만 호출
}

resource "aws_lambda_permission" "addon_lamget_cloudfront_url" {
  statement_id           = "AllowCloudFrontInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.addon_lamget.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.<기존>.arn
  function_url_auth_type = "AWS_IAM"
}

# OAC 문서는 InvokeFunctionUrl 과 함께 InvokeFunction 도 부여하도록 안내
resource "aws_lambda_permission" "addon_lamget_cloudfront_invoke" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.addon_lamget.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.<기존>.arn
}

resource "aws_cloudfront_origin_access_control" "addon_lamget" {
  name                              = "${var.addon_lamget_function_name}-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AllViewerExceptHostHeader 는 Authorization 을 전달해 OAC 서명과 충돌(403) — 쿼리스트링만 전달
resource "aws_cloudfront_origin_request_policy" "addon_lamget" {
  name = "${var.addon_lamget_function_name}-orp"
  query_strings_config {
    query_string_behavior = "all"
  }
  headers_config {
    header_behavior = "none"
  }
  cookies_config {
    cookie_behavior = "none"
  }
}
```

```hcl
# aws_cloudfront_distribution 리소스 안에 (기존 origin/behavior 는 그대로 두고 추가):
origin {
  origin_id                = "addon-lambda-origin"
  domain_name              = trimsuffix(trimprefix(aws_lambda_function_url.addon_lamget.function_url, "https://"), "/")
  origin_access_control_id = aws_cloudfront_origin_access_control.addon_lamget.id

  custom_origin_config {
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"
    origin_ssl_protocols   = ["TLSv1.2"]
  }
}

ordered_cache_behavior {
  path_pattern             = "/v1/book*"
  target_origin_id         = "addon-lambda-origin"
  viewer_protocol_policy   = "redirect-to-https"
  allowed_methods          = ["GET", "HEAD"]
  cached_methods           = ["GET", "HEAD"]
  cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  origin_request_policy_id = aws_cloudfront_origin_request_policy.addon_lamget.id
}
```

### (c) API Gateway REST

새 REST API 가 필요하면 `set-05/task-2/module-4-rest-api/terraform/apigw.tf` 를 통째로 복사한다
(`aws_api_gateway_rest_api` → resource → method(`request_validator`) → `AWS_PROXY` integration →
`aws_lambda_permission`(`apigateway.amazonaws.com`, `${execution_arn}/*/*`) → deployment → stage).
`index.py` 는 API GW proxy 이벤트(`queryStringParameters`)도 같은 코드로 처리한다. 스테이지 강화는 apigw-hardening 키트.

## 함정

- **응답 필드 순서**가 채점 항목이다(set-03 mark 9-3, set-02 mark 9-2). `addon_lamget_fields` 를 채점지 예상 출력 순서대로. 값은 `ensure_ascii=False` 로 비ASCII 그대로 출력.
- `statusDescription` 은 ALB 통합 응답에만 필요하고 `index.py` 가 `requestContext.elb` 유무로 자동 판단한다. Function URL·API GW 이벤트에는 넣지 않는다.
- ALB 는 쿼리스트링을 URL 디코딩하지 않는다 → `unquote_plus`. 공백 포함 값(`2ND%20TINY_CON`) 채점이 있다.
- 테이블이 SSE-KMS(CMK) 면 `addon_lamget_table_kms_key_arn` 필수 — 없으면 GetItem 이 AccessDenied.
- GSI Query 는 `dynamodb:Query` + `<table arn>/index/*` 리소스 둘 다 있어야 한다(정책에 포함됨).
- ALB Lambda TG 이름 32자 제한 — `substr(...,0,29)-tg` 로 잘린다. 과제지가 TG 이름을 지정하면 `name` 을 그 값으로 고정.
- `aws_lb_target_group_attachment` 는 `aws_lambda_permission` 뒤여야 한다(없으면 등록 실패). `depends_on` 이 걸려 있다.
- 리스너 규칙 priority 중복이면 apply 실패(`PriorityInUse`) — 기존 규칙 번호 먼저 확인.
- (b) `origin_request_policy` 로 `AllViewerExceptHostHeader` 를 쓰면 Authorization 헤더 전달로 OAC 서명 충돌 → 403. 쿼리스트링만 전달하는 ORP 를 쓴다.
- (b) Function URL `authorization_type = "NONE"` 이면 OAC 없이도 되지만 인터넷 공개 — 과제지가 CloudFront 경유만 허용하면 `AWS_IAM`.
- (b) CloudFront 배포 변경은 in-place 지만 전파 수 분. `wait_for_deployment = false` 면 apply 는 바로 끝난다.
- `python3.14` 런타임을 과제지가 명시하면 `addon_lamget_runtime` 으로 바꾼다(set-02·set-05 는 3.14).
- 1과제 Lambda 는 기본 non-VPC(DynamoDB 퍼블릭 엔드포인트). "Private Subnet 내 운용" 요구 시 lambda-hardening 키트 `vpc_config` 블록 + 인라인 ENI 권한.

## 실전 구현 (참고용)

- `set-07/task-1/terraform/lambda.tf`·`lambda/index.py`·`alb.tf` — GetItem + 선택 필터, ALB default → Lambda
- `set-05/task-1/terraform/lambda.tf`·`lambda/index.py`·`alb.tf` — VPC Lambda, GET/POST 경로 분기 규칙
- `set-03/task-1/terraform/lambda.tf`·`lambda/index.py`·`cloudfront.tf` — GSI Query, Function URL(AWS_IAM) + OAC + ORP
- `set-02/task-1/terraform/lambda.tf`·`lambda/index.py` — GSI Query 전건 최신순 배열 응답, `unquote_plus`
- `set-05/task-2/module-4-rest-api/terraform/apigw.tf` — API Gateway REST + Lambda proxy
