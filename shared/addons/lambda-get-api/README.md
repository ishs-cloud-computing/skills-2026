# Lambda GET API 부착 KIT

DynamoDB 조회 Lambda(쿼리스트링 필수값 400 · 없으면 404 JSON · **응답 필드 순서 고정**)를 새로 만들고, (a) ALB → Lambda / (b) Function URL + CloudFront / (c) API Gateway REST 중 하나로 노출한다.

## 이 KIT이 맞나

- 과제지에 **"REST API"·"GET API를 구성"·"조회 API"** 가 새 문항으로 나왔다 → 맞다.
- **기존 함수 강화**(동시성·Function URL·DLQ) → [lambda-hardening](../lambda-hardening/README.md).
- **세 세트 모두 이미 조회 Lambda가 있다.** 처음부터 쓰는 것보다 **그 세트의 `lambda.tf` + `lambda/index.py` 를 복사**하는 쪽이 빠르다.

## 세트별 기존 구현 — 어느 것을 복사할까

| 세트 | 조회 방식 | 노출 경로 | 특징 |
| --- | --- | --- | --- |
| **set-07** | 테이블 PK `GetItem` | **(a)** ALB default → Lambda TG | 가장 단순. `unicorn-get-booking-func`, python3.13 |
| **set-03** | GSI `booking_id-index` Query | **(b)** CloudFront → Function URL(`AWS_IAM`) + OAC + ORP | OAC 서명 충돌까지 해결된 완성본 |
| **set-02** | GSI `concert_name-created_at-index` Query, 최신순 배열 | **(a)** ALB 리스너 규칙 → Lambda TG | `unquote_plus`(공백 포함 값) 처리 |

## 복사할 파일

| 원본 | 대상 | 언제 |
| --- | --- | --- |
| `lambda-get-api.tf` | `set-XX/task-1/terraform/` | 항상 — 함수·최소권한 역할·선생성 로그 그룹 |
| `alb-lambda.tf` | `set-XX/task-1/terraform/` | (a) ALB 노출 시. `addon_lamget_alb_listener_arn` 이 비면 전부 생성 안 함 |
| `lambda/index.py` | `set-XX/task-1/terraform/lambda-get/index.py` | 세 세트 모두 `lambda/index.py` 가 이미 있다 — 디렉터리를 바꾸고 `data "archive_file"` 의 `source_file` 을 맞춘다 |
| `variables.tf` | `variables-lamget-addon.tf` | `addon_lamget_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_lamget_function_name` | **필수** | 함수 이름. **과제지 명시 이름과 정확히 일치.** 역할·정책·로그 그룹 이름이 여기서 파생 |
| `addon_lamget_table_name` | **필수** | 조회 대상 테이블 이름 |
| `addon_lamget_table_arn` | **필수** | 테이블 ARN (최소권한 리소스 한정) |
| `addon_lamget_runtime` | `"python3.13"` | 과제지 명시 버전으로 |
| `addon_lamget_key_name` | `"booking_id"` | 쿼리스트링 필수 파라미터 = PK(또는 GSI PK) 속성명. 없으면 400 |
| `addon_lamget_index_name` | `""` | 비우면 PK `GetItem`, 채우면 GSI Query |
| `addon_lamget_fields` | 6개 배열 | **200 응답 JSON 필드 순서.** 채점지 예상 출력 순서와 동일하게 |
| `addon_lamget_table_kms_key_arn` | `""` | 테이블이 CMK면 키 ARN — 없으면 GetItem이 AccessDenied |
| `addon_lamget_log_retention_days` | `30` | 로그 보존 기간 |
| `addon_lamget_alb_listener_arn` | `""` | (a) 규칙을 붙일 리스너 ARN |
| `addon_lamget_alb_rule_priority` | `30` | 기존 규칙과 겹치지 않게 |
| `addon_lamget_alb_path` | `"/v1/book"` | GET 경로 패턴 |
| `addon_lamget_alb_header_name` / `_value` | `""` | 기존 규칙이 origin-verify 헤더를 검사하면 같은 값 |

<details><summary><b>값 뽑기 — 세트별 (tfvars 그대로 붙여넣기)</b></summary>

필요한 output을 먼저 넣는다:

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "table_name"       { value = aws_dynamodb_table.data.name }    # set-03 .book / set-07 .concert
output "table_arn"        { value = aws_dynamodb_table.data.arn }
output "app_listener_arn" { value = aws_lb_listener.book.arn }        # set-07 은 .app / set-03 은 없음
```

```powershell
terraform output -raw table_name
terraform output -raw table_arn
terraform output -raw app_listener_arn
terraform output -raw db_kms_arn      # set-03 (테이블 CMK)
terraform output -raw app_kms_arn     # set-07 (테이블 CMK)
```

| 세트 | `key_name` | `index_name` | `table_kms_key_arn` | 리스너 |
| --- | --- | --- | --- | --- |
| set-02 | `client_id`(PK) 또는 `concert_name`(GSI) | `concert_name-created_at-index` | `aws_kms_key.dynamodb.arn` (output 없음 → 추가) | `aws_lb_listener.book.arn` |
| set-03 | `booking_id` (GSI PK) | `booking_id-index` | `terraform output -raw db_kms_arn` | **없음** — (b)로 간다 |
| set-07 | `booking_id` (PK) | `""` (GetItem) | `terraform output -raw app_kms_arn` | `aws_lb_listener.app.arn` |

```hcl
# 파일: set-07/task-1/terraform/terraform.tfvars — 예시
addon_lamget_function_name     = "unicorn-get-booking-func-2"
addon_lamget_runtime           = "python3.13"
addon_lamget_table_name        = "unicorn-concert-db"
addon_lamget_table_arn         = "<terraform output -raw table_arn 값>"
addon_lamget_key_name          = "booking_id"
addon_lamget_index_name        = ""
addon_lamget_fields            = ["booking_id", "client_id", "username", "email", "concert_name", "created_at"]
addon_lamget_table_kms_key_arn = "<terraform output -raw app_kms_arn 값>"
addon_lamget_alb_listener_arn  = "<terraform output -raw app_listener_arn 값>"
addon_lamget_alb_rule_priority = 30
addon_lamget_alb_path          = "/v1/book"
```
</details>

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # 기존 리소스 diff 가 없어야 한다
terraform apply
```

## 0. 함수 자체의 output

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "addon_lamget_function_name" { value = aws_lambda_function.addon_lamget.function_name }
output "addon_lamget_function_arn"  { value = aws_lambda_function.addon_lamget.arn }
output "addon_lamget_log_group"     { value = aws_cloudwatch_log_group.addon_lamget.name }
```

```powershell
terraform output -raw addon_lamget_function_name
aws logs tail (terraform output -raw addon_lamget_log_group) --since 5m --follow
```

## (a) ALB → Lambda

```hcl
# 파일: set-XX/task-1/terraform/alb-lambda.tf   (KIT에서 복사됨)
resource "aws_lb_listener_rule" "addon_lamget" {
  listener_arn = var.addon_lamget_alb_listener_arn
  priority     = var.addon_lamget_alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.addon_lamget.arn
  }

  condition {
    path_pattern { values = [var.addon_lamget_alb_path] }
  }
  condition {
    http_request_method { values = ["GET"] }
  }
}
```

<details><summary><b>값 뽑기 — 세트별 (priority 충돌을 먼저 본다)</b></summary>

| 세트 | 기존 규칙 | 새 규칙 priority | 헤더 조건 |
| --- | --- | --- | --- |
| set-02 | `.book_post` · `.book_lambda` (헤더 조건 있음) | 기존 번호 확인 후 그 다음 | **필수** — 안 달면 헤더 없는 직접 호출이 Lambda로 샌다 |
| set-03 | 리스너 없음 (Ingress) | — | (b)로 간다 |
| set-07 | `.health`(10) · `.post`(20), default → Lambda | `30` | 불필요 (internal ALB + VPC Origin) |

```powershell
# 기존 priority — 중복이면 apply 가 PriorityInUse 로 실패한다
aws elbv2 describe-rules --listener-arn (terraform output -raw app_listener_arn) `
  --query "Rules[].[Priority,Conditions[].Field,Actions[0].Type]" --output table

# 새 Lambda 타깃그룹
aws elbv2 describe-target-groups `
  --query "TargetGroups[?TargetType=='lambda'].[TargetGroupName,TargetGroupArn]" --output table

# 동작 확인 — 이 3개가 채점 형태다
$dns = terraform output -raw book_alb_dns      # set-07 은 alb_dns_name (internal — VPC 안에서)
curl.exe -s "http://$dns/v1/book?booking_id=B001"                             # 200 JSON
curl.exe -s -o NUL -w "%{http_code}`n" "http://$dns/v1/book"                  # 400
curl.exe -s -o NUL -w "%{http_code}`n" "http://$dns/v1/book?booking_id=ZZZ"   # 404
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "addon_lamget_tg_arn" { value = aws_lb_target_group.addon_lamget.arn }
```

ALB Lambda TG 이름은 **32자 제한**이라 KIT이 `substr(...,0,29)-tg` 로 자른다. 과제지가 TG 이름을 지정하면 `name` 을 그 값으로 고정한다.
</details>

## (b) Function URL + CloudFront

```hcl
# 파일: set-XX/task-1/terraform/lambda-get-api.tf
resource "aws_lambda_function_url" "addon_lamget" {
  function_name      = aws_lambda_function.addon_lamget.function_name
  authorization_type = "AWS_IAM"    # CloudFront OAC(SigV4) 로만 호출
}

resource "aws_lambda_permission" "addon_lamget_cloudfront_url" {
  statement_id           = "AllowCloudFrontInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.addon_lamget.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.cdn.arn    # ← 세트별 주소
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "addon_lamget_cloudfront_invoke" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.addon_lamget.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.cdn.arn
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
  query_strings_config { query_string_behavior = "all" }
  headers_config { header_behavior = "none" }
  cookies_config { cookie_behavior = "none" }
}
```

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 aws_cloudfront_distribution 리소스 블록 *안에* (기존 origin/behavior 는 그대로 두고 추가)
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
  cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"   # Managed-CachingDisabled
  origin_request_policy_id = aws_cloudfront_origin_request_policy.addon_lamget.id
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 배포 주소 | 이미 있는 Lambda OAC |
| --- | --- | --- |
| set-02 | `aws_cloudfront_distribution.cdn.arn` | 없음 |
| set-03 | `aws_cloudfront_distribution.cdn[0].arn` | `aws_cloudfront_origin_access_control.lambda` + `aws_cloudfront_origin_request_policy.lambda_get` **이미 있음** — 재사용한다 |
| set-07 | `aws_cloudfront_distribution.cdn.arn` | 없음 |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "addon_lamget_function_url" { value = aws_lambda_function_url.addon_lamget.function_url }
output "cloudfront_id"             { value = aws_cloudfront_distribution.cdn.id }   # set-03 은 cdn[0].id
```

```powershell
terraform output -raw addon_lamget_function_url
$d = terraform output -raw cloudfront_domain

# 배포 전파를 기다린다 (Deployed 여야 반영 끝)
aws cloudfront get-distribution --id (terraform output -raw cloudfront_id) --query "Distribution.Status"

curl.exe -s "https://$d/v1/book?booking_id=B001"                            # 200
curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/v1/book"                 # 400
curl.exe -s -o NUL -w "%{http_code}`n" (terraform output -raw addon_lamget_function_url)   # 403 (AWS_IAM — 정상)
```

set-03은 이미 이 구성이 완성돼 있다. 새로 만들지 말고 **`cloudfront.tf` 의 `lambda-origin` 블록을 복사**하는 쪽이 빠르다.
</details>

<details><summary><b>(c) API Gateway REST — task-1 세 세트에는 API Gateway가 없다</b></summary>

`aws_api_gateway_rest_api` → `resource` → `method`(+`request_validator`) → `AWS_PROXY` integration → `aws_lambda_permission`(`apigateway.amazonaws.com`, `${execution_arn}/*/*`) → `deployment` → `stage`.

`index.py` 는 API GW proxy 이벤트(`queryStringParameters`)도 같은 코드로 처리한다.

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "addon_lamget_api_url" {
  value = "${aws_api_gateway_stage.addon.invoke_url}/v1/book"
}
```

```powershell
terraform output -raw addon_lamget_api_url
curl.exe -s "$(terraform output -raw addon_lamget_api_url)?booking_id=B001"
```

스테이지 강화(액세스 로그·스로틀·Usage Plan)는 [apigw-hardening](../apigw-hardening/README.md).
</details>

## VERIFY

```powershell
$fn = terraform output -raw addon_lamget_function_name
aws lambda get-function-configuration --function-name $fn --query "[Runtime,Handler,Timeout,Environment.Variables]"
aws logs tail (terraform output -raw addon_lamget_log_group) --since 5m

curl.exe -s "<엔드포인트>?booking_id=B001"     # 200 + 필드 순서 고정 JSON
curl.exe -s "<엔드포인트>"                      # 400
curl.exe -s "<엔드포인트>?booking_id=ZZZ"       # 404 JSON
```

## TROUBLESHOOT

- **응답 필드 순서가 채점 항목이다** (set-03 mark 9-3, set-02 mark 9-2). `addon_lamget_fields` 를 채점지 예상 출력 순서대로. 값은 `ensure_ascii=False` 로 비ASCII 그대로 출력한다.
- `statusDescription` 은 **ALB 통합 응답에만** 필요하다. `index.py` 가 `requestContext.elb` 유무로 자동 판단한다.
- **ALB는 쿼리스트링을 URL 디코딩하지 않는다** → `unquote_plus`. 공백 포함 값(`2ND%20TINY_CON`) 채점이 있다.
- 테이블이 SSE-KMS면 `addon_lamget_table_kms_key_arn` 필수 — 없으면 GetItem이 AccessDenied.
- GSI Query는 `dynamodb:Query` + `<table arn>/index/*` 리소스 둘 다 필요하다.
- ALB Lambda TG 이름 **32자 제한**.
- `aws_lb_target_group_attachment` 는 `aws_lambda_permission` 뒤여야 한다 (`depends_on`).
- 리스너 규칙 priority 중복이면 `PriorityInUse`.
- (b) `AllViewerExceptHostHeader` ORP를 쓰면 Authorization 전달로 **OAC 서명 충돌 → 403**. 쿼리스트링만 전달하는 ORP를 쓴다.
- (b) CloudFront 배포 변경은 in-place지만 전파에 수 분. `wait_for_deployment = false` 면 apply는 바로 끝난다.
- 1과제 Lambda는 기본 non-VPC(DynamoDB 퍼블릭 엔드포인트). "Private Subnet 내 운용" 요구 시 [lambda-hardening](../lambda-hardening/README.md) 6번 + ENI 권한.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/lambda.tf` · `lambda/index.py` · `alb.tf` — GetItem + 선택 필터, ALB default → Lambda
- set-03 task-1 `terraform/lambda.tf` · `lambda/index.py` · `cloudfront.tf` — GSI Query, Function URL(AWS_IAM) + OAC + ORP
- set-02 task-1 `terraform/lambda.tf` · `lambda/index.py` — GSI Query 전건 최신순 배열 응답, `unquote_plus`

---

## 막히면 여는 순서

인자 이름이나 조합에서 막히면 ① 위 **실전 구현**(이미 apply 가 통과한 코드) → ② 로컬 스키마 명령 → ③ 공식 문서 순으로 연다. 대회장 인터넷은 공식 문서까지 열려 있다. 그래도 ①②를 먼저 여는 건 브라우저보다 빠르고, 블로그에서 인자 이름을 베껴 프로바이더·차트 버전이 어긋나는 일이 없어서다.

```powershell
terraform providers schema -json | jq '.provider_schemas[].resource_schemas["<리소스타입>"].block.attributes | keys'
aws <서비스> <명령> help
kubectl explain <리소스>.spec --recursive
```

리소스별 공식 문서 주소·이 저장소의 구현 위치·흔히 막히는 인자는 [DOC-LINKS 4절 리소스별 색인](../../../DOC-LINKS.md#4-리소스별-색인)에 한 줄씩 있다. 리소스 타입(`aws_s3_bucket` 등)으로 Ctrl+F 한다.

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), 세트별 리소스 주소는 [대조표](../../../KIT-INDEX.md#세트별-리소스-주소-대조표-task-1)(표에 없는 세트는 [주소 찾는 명령](../../../KIT-INDEX.md#표에-없는-세트는-직접-찾는다)), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
