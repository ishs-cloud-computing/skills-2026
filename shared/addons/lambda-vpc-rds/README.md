# lambda-vpc-rds 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

task-3 당일 추가 문항 "신규 Lambda 개발" 용: VPC 내 Lambda(private 서브넷 + DB SG) → 기존 RDS Proxy(MySQL) 조회,
Function URL 을 기존 CloudFront 에 origin/behavior 로 연결. 대응 후보: task-3.

> ⚠ task-3 기본 규정은 **Lambda 금지**(task-sample 15 "어떠한 목적으로든 Fargate·Lambda 불가", mark-sample 0-4
> "Lambda 부적절 사용 시 전체 0점"). 이 키트는 **당일 과제지가 Lambda 를 명시 허용·요구할 때만** 붙인다.
> 허용 문구가 없으면 절대 붙이지 않는다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 5개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_lamvpc_function_name` | **필수** | Lambda 함수 이름. 과제지 명시 이름과 정확히 일치. 역할·SG·로그 그룹 이름이 여기서 파생된다 |
| `addon_lamvpc_vpc_id` | **필수** | 기존 VPC ID (Lambda SG 생성용) |
| `addon_lamvpc_subnet_ids` | **필수** | Lambda ENI 를 둘 기존 private 서브넷 ID 목록 (RDS Proxy 와 같은 VPC) |
| `addon_lamvpc_proxy_endpoint` | **필수** | 기존 RDS Proxy 엔드포인트 호스트명 (aws_db_proxy.<x>.endpoint) |
| `addon_lamvpc_secret_arn` | **필수** | DB 자격증명 Secrets Manager 시크릿 ARN ({username,password} JSON). Proxy 가 쓰는 시크릿과 같은 것 |
| `addon_lamvpc_runtime` | `"python3.13"` | Lambda 런타임. 과제지 명시 버전으로. pymysql 은 순수 파이썬이라 버전 무관 |
| `addon_lamvpc_db_sg_id` | `""` | 기존 RDS/Proxy SG ID. 이 SG 에 Lambda SG → DB 포트 인바운드를 추가한다. 이미 0.0.0.0/0 이면 빈 문자열로 생략 |
| `addon_lamvpc_db_port` | `3306` | DB 포트 |
| `addon_lamvpc_db_name` | `"dev"` | 접속 DB 이름 |
| `addon_lamvpc_table` | `"product"` | 조회 대상 테이블 이름 (SQL 식별자 — 영숫자·_ 만) |
| `addon_lamvpc_key_column` | `"id"` | 쿼리스트링 필수 파라미터 = WHERE 컬럼 이름 (SQL 식별자 — 영숫자·_ 만) |
| `addon_lamvpc_url_auth_type` | `"AWS_IAM"` | Function URL 인증. CloudFront OAC 뒤면 AWS_IAM, 직접 노출이면 NONE |
| `addon_lamvpc_log_retention_days` | `7` | 로그 그룹 보존 기간(일) |

## KEEP — 건드리지 않는다

- 기존 세트의 리소스·이름·CIDR. 이름이 충돌하면 기존 것을 지우지 말고 **이 KIT 쪽 변수를 리네임**한다.
- 공식 지급물 — `provided/`, `task.md`, `mark.md`, `mark*.sh`.
- `plan` 에 기존 리소스의 replace/delete 가 보이면 apply 하지 말고 멈춘다.

## CHECK — apply 전 계정·리전

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
```

## RUN

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 Kit의 state를 건드리지 않는다.

```powershell
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

복사할 파일과 순서는 아래 본문을 따른다.

## VERIFY / SCORE

- **VERIFY** = 이 README 본문의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 아래 함정은 이 KIT 고유 문제다.

## 파일

- `lambda-vpc-rds.tf` — Lambda SG, DB SG 인바운드(선택), 최소권한 역할(ENI·시크릿·로그), 선생성 로그 그룹, 함수(`vpc_config`), Function URL, output.
- `lambda/index.py` — `GET ?<KEY_COLUMN>=값` → `SELECT * FROM <TABLE> WHERE <KEY_COLUMN>=?`. 400/404/200 JSON.
- `variables.tf` — `addon_lamvpc_*` 변수.
- CloudFront 연결 블록은 아래 `## 블록`.

## 부착 절차

1. `lambda-vpc-rds.tf`·`variables.tf` 를 `task-3/terraform/` 으로, `lambda/index.py` 를 `task-3/terraform/lambda/` 로 복사한다.
2. pymysql 동봉 (Windows PowerShell, `task-3/terraform` 에서):

   ```powershell
   pip install pymysql -t lambda/
   ```

   `lambda/pymysql/__init__.py` 가 없으면 plan 이 precondition 으로 막힌다.
3. `terraform.tfvars` 에 주입 (task-3 기준 값은 `locals.tf`·`rds-proxy.tf` 에서 읽는다):

   ```hcl
   addon_lamvpc_function_name  = "skills-product-query"
   addon_lamvpc_runtime        = "python3.13"
   addon_lamvpc_vpc_id         = "vpc-0123456789abcdef0"
   addon_lamvpc_subnet_ids     = ["subnet-aaaa", "subnet-bbbb"]
   addon_lamvpc_db_sg_id       = "" # task-3 db SG 는 이미 0.0.0.0/0 → 생략
   addon_lamvpc_db_port        = 3306
   addon_lamvpc_proxy_endpoint = "skills-db-proxy.proxy-xxxx.ap-northeast-2.rds.amazonaws.com"
   addon_lamvpc_db_name        = "dev"
   addon_lamvpc_secret_arn     = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:skills-db-credentials-AbCdEf"
   addon_lamvpc_table          = "product"
   addon_lamvpc_key_column     = "id"
   addon_lamvpc_url_auth_type  = "AWS_IAM"
   ```

   task-3 에서는 변수 대신 직접 참조가 빠르다: `var.addon_lamvpc_vpc_id` → `aws_vpc.this.id`,
   `var.addon_lamvpc_subnet_ids` → `aws_subnet.private[*].id`, `var.addon_lamvpc_proxy_endpoint` → `aws_db_proxy.this.endpoint`,
   `var.addon_lamvpc_secret_arn` → `aws_secretsmanager_secret.db.arn`, `var.addon_lamvpc_db_port` → `local.db_port`.
4. `terraform fmt` → `validate` → `plan` 으로 기존 리소스 diff 없음 확인 → `apply`.
5. CloudFront 연결 블록(아래)을 `cloudfront.tf` 에 추가 → 다시 `plan`(배포 in-place) → `apply`.
6. 확인: `curl "https://<CloudFront 도메인>/api/query?id=1"`. 누락 → 400, 없는 값 → 404.

## 블록

### Function URL → 기존 CloudFront

```hcl
# 새 블록 (lambda-vpc-rds.tf 끝 또는 cloudfront.tf):
resource "aws_lambda_permission" "addon_lamvpc_cloudfront_url" {
  statement_id           = "AllowCloudFrontInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.addon_lamvpc.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "addon_lamvpc_cloudfront_invoke" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.addon_lamvpc.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn
}

resource "aws_cloudfront_origin_access_control" "addon_lamvpc" {
  name                              = "${var.addon_lamvpc_function_name}-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AllViewerExceptHostHeader 는 Authorization 전달로 OAC 서명과 충돌(403) — 쿼리스트링만
resource "aws_cloudfront_origin_request_policy" "addon_lamvpc" {
  name = "${var.addon_lamvpc_function_name}-orp"
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
# aws_cloudfront_distribution.this 리소스 안에 (기존 origin/behavior 유지, 추가):
origin {
  origin_id                = "addon-lambda-origin"
  domain_name              = trimsuffix(trimprefix(aws_lambda_function_url.addon_lamvpc.function_url, "https://"), "/")
  origin_access_control_id = aws_cloudfront_origin_access_control.addon_lamvpc.id

  custom_origin_config {
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"
    origin_ssl_protocols   = ["TLSv1.2"]
  }
}

ordered_cache_behavior {
  path_pattern             = "/api/query*" # 과제지 경로로
  target_origin_id         = "addon-lambda-origin"
  viewer_protocol_policy   = "allow-all"
  allowed_methods          = ["GET", "HEAD"]
  cached_methods           = ["GET", "HEAD"]
  cache_policy_id          = local.cache_caching_disabled
  origin_request_policy_id = aws_cloudfront_origin_request_policy.addon_lamvpc.id
}
```

## TROUBLESHOOT — 이 KIT 고유 함정
- **0점 함정**: 과제지 허용 문구 없이 Lambda 를 만들면 task-3 전체 0점(mark 0-4). 허용 문구 확인 후 부착.
- task-3 WAF(`waf.tf`) 는 `waf_api_path_regexes` 에 없는 경로를 통과시켜 ALB 404 로 보낸다. CloudFront 의 새 behavior 는 ALB 앞이 아니라 Lambda origin 이므로 WAF 룰의 scope-down 에는 걸리지 않는다. 과제지가 새 경로도 WAF 검사 대상으로 요구하면 `waf_api_path_regexes` 에 추가.
- CloudFront 는 origin 경로를 그대로 Function URL 에 보낸다(`/api/query?id=1`). `index.py` 는 경로를 보지 않고 쿼리스트링만 읽는다. 경로를 벗기려면 task-3 `cloudfront.tf` 의 `aws_cloudfront_function` strip 패턴.
- Lambda 는 private 서브넷에서 **Secrets Manager** 에 닿아야 한다 — task-3 는 NAT 가 있어 통과. NAT 없는 세트면 Secrets Manager VPC 엔드포인트 또는 시크릿 대신 env(DB_USER/DB_PASSWORD — 평문 노출 감점 가능).
- Proxy 는 `require_tls = false`·`MYSQL_NATIVE_PASSWORD` (task-3). Proxy 를 새로 만든 세트에서 `require_tls = true` 면 `pymysql.connect(ssl={"ca": ...})` 필요 — pymysql 기본은 non-TLS.
- `vpc_config` 최초 apply 는 ENI 생성 1~2분. destroy 시 ENI 정리로 최대 20분 — teardown 시간에 반영.
- `aws_vpc_security_group_ingress_rule` 로 DB SG 에 규칙을 추가하면 기존 SG 가 인라인 `ingress {}` 블록을 쓰는 경우 plan 마다 diff 가 난다. task-3 `rds-proxy.tf` 의 db SG 는 인라인 + 0.0.0.0/0 이라 `addon_lamvpc_db_sg_id = ""` 로 생략한다.
- pymysql 을 동봉하지 않으면 런타임 `ImportError` — precondition 이 plan 에서 막는다. `pip` 가 Windows 전용 wheel 을 넣을 수 있으나 pymysql 은 순수 파이썬이라 무관.
- 테이블·컬럼 이름은 SQL 식별자라 바인딩 불가 → `^[A-Za-z0-9_]+$` 검사. 과제지 테이블명에 `-` 가 있으면 `index.py` 정규식을 넓힌다.
- Function URL `AWS_IAM` 은 OAC 없는 직접 호출 403 이 정상. `NONE` 으로 바꾸면 인터넷 공개.
- 1과제용 DynamoDB 조회 Lambda 는 이 키트가 아니라 lambda-get-api 키트.

## 실전 구현 (참고용)

- `task-3/terraform/rds-proxy.tf` — Proxy·시크릿·DB SG
- `task-3/terraform/cloudfront.tf` — 기존 배포(`local.cache_caching_disabled`, strip Function)
- `set-05/task-1/terraform/lambda.tf` — `vpc_config` + 인라인 ENI 권한 + Lambda SG
- `set-03/task-1/terraform/lambda.tf`·`cloudfront.tf` — Function URL(AWS_IAM) + OAC + ORP
- `set-02/task-2/module-3-msk/terraform/lambda.tf` — 의존성 zip 동봉 precondition 패턴

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
