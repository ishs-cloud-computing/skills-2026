# DynamoDB 강화 부착 KIT

기존 테이블에 TTL·PITR·삭제 방지·CMK·Streams·GSI를 **in-place** 로 덧붙이고, Streams → Lambda ESM과 Gateway 엔드포인트를 새 리소스로 붙인다.

## 이 KIT이 맞나

- 과제지 기존 DynamoDB 문항 뒤에 **"TTL"·"PITR"·"스트림"·"삭제 방지"·"GSI 추가"** 가 붙었다 → 맞다.
- **CMK로만** 암호화 → [kms](../kms/README.md) 2번 블록도 같다.
- 아래 블록은 전부 in-place다. 단 `hash_key`·`range_key`·`name`·`billing_mode` 를 건드리면 **재생성** — 손대지 않는다.

## 세트별 현재 테이블 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 리소스 | `aws_dynamodb_table.data` | `aws_dynamodb_table.book` | `aws_dynamodb_table.concert` |
| 이름 | `var.table_name` | `var.table_name` | `"unicorn-concert-db"` (하드코딩) |
| PK | `client_id` | `client_id` | `booking_id` |
| GSI | `concert_name-created_at-index` | `booking_id-index` | `client-id-created-at-index` (`// do not change`) |
| PITR | 켜짐 (기간 미지정) | 켜짐 **35일** | 켜짐 (기간 미지정) |
| 삭제 방지 | 켜짐 | 켜짐 | 켜짐 |
| SSE CMK | `aws_kms_key.dynamodb` | `aws_kms_key.db` | `aws_kms_key.app` |
| TTL | **없음** | **없음** | **없음** |
| Streams | **없음** | **없음** | **없음** |
| 리소스 정책 | 없음 | `aws_dynamodb_resource_policy.book` | 없음 |
| 이름 output | **없음** | `table_name` (있음) | **없음** |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "table_name" { value = aws_dynamodb_table.data.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "table_name" { value = aws_dynamodb_table.concert.name }
```

```powershell
terraform output -raw table_name
```

## 복사할 파일

| 원본 | 대상 | 언제 |
| --- | --- | --- |
| `dynamodb-stream.tf` | `set-XX/task-1/terraform/` | Streams → Lambda ESM이 필요할 때 |
| `dynamodb-endpoint.tf` | `set-XX/task-1/terraform/` | DynamoDB Gateway 엔드포인트가 필요할 때 |
| `variables.tf` | `variables-ddb-addon.tf` | **쓰는 `.tf` 의 절만** 복사한다 — 다른 절의 필수 변수가 남으면 plan이 값을 묻는다 |

TTL·PITR·삭제 방지·SSE·Streams·GSI는 파일 복사가 아니라 기존 `aws_dynamodb_table` 안에 넣는 **블록**이다.

## CHANGE — 당일 고치는 값

`terraform.tfvars`. **필수 5개** — 같은 루트 모듈이면 tfvars 대신 리소스 직접 참조가 안전하다.

| 변수 | 기본값 | 직접 참조로 바꿀 값 |
| --- | --- | --- |
| `addon_ddb_stream_arn` | **필수** | `aws_dynamodb_table.<기존>.stream_arn` |
| `addon_ddb_lambda_function_name` | **필수** | `aws_lambda_function.<기존>.function_name` |
| `addon_ddb_lambda_role_name` | **필수** | `aws_iam_role.<기존>.name` |
| `addon_ddb_vpc_id` | **필수** | `aws_vpc.this.id` |
| `addon_ddb_route_table_ids` | **필수** | `[for k in local.private_subnet_keys : aws_route_table.private[k].id]` (set-03은 `.app[k]`) — 세 세트 모두 `for_each` 맵이다 |
| `addon_ddb_esm_batch_size` | `100` | Streams 최대 10000 |
| `addon_ddb_esm_max_retry_attempts` | `-1` | -1 = 무제한. 과제지가 "재시도 N회"면 그 값 |
| `addon_ddb_esm_bisect_on_error` | `false` | poison record 격리 |
| `addon_ddb_esm_on_failure_arn` | `""` | 실패 레코드 SQS/SNS ARN. 빈 문자열이면 블록 생략 |
| `addon_ddb_endpoint_name` | `"dynamodb-endpoint"` | 엔드포인트 Name 태그 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # 기존 테이블이 update in-place 만 떠야 한다 (replace 없음)
terraform apply
```

## 1. TTL

```hcl
# 파일: set-XX/task-1/terraform/dynamodb.tf
# 기존 aws_dynamodb_table 리소스 블록 *안에* — 속성값은 epoch 초(Number)
ttl {
  attribute_name = "expires_at"
  enabled        = true
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 TTL이 **없다** — 새로 넣는다. 속성명은 과제지 지정값과 정확히 일치시킨다.

```powershell
aws dynamodb describe-time-to-live --table-name (terraform output -raw table_name)
# → {"TimeToLiveDescription":{"AttributeName":"expires_at","TimeToLiveStatus":"ENABLED"}}
```

TTL은 만료 후 **최대 48시간** 뒤 삭제된다. 채점은 보통 `TimeToLiveStatus=ENABLED` + 속성명만 본다. 속성값이 문자열이면 영원히 만료되지 않는다.
</details>

## 2. PITR

```hcl
# 파일: set-XX/task-1/terraform/dynamodb.tf
# 기존 aws_dynamodb_table 리소스 블록 *안에*
point_in_time_recovery {
  enabled                 = true
  recovery_period_in_days = 35   # 1~35. 과제지가 "최장" 이면 35
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 현재 | 과제지가 기간을 지정하면 |
| --- | --- | --- |
| set-02 | `enabled = true` (기간 미지정) | `recovery_period_in_days` 한 줄 추가 |
| set-03 | `enabled = true`, **35일 명시** (mark 2-1이 35를 읽는다) | 그대로 |
| set-07 | `enabled = true` (기간 미지정) | `recovery_period_in_days` 한 줄 추가 |

```powershell
aws dynamodb describe-continuous-backups --table-name (terraform output -raw table_name) `
  --query "ContinuousBackupsDescription.PointInTimeRecoveryDescription"
```
</details>

## 3. 삭제 방지 · CMK 암호화

```hcl
# 파일: set-XX/task-1/terraform/dynamodb.tf
# 기존 aws_dynamodb_table 리소스 블록 *안에*
deletion_protection_enabled = true

server_side_encryption {
  enabled     = true
  kms_key_arn = aws_kms_key.dynamodb.arn   # ← 세트별 키로 치환
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 키 리소스 | 키 ARN output |
| --- | --- | --- |
| set-02 | `aws_kms_key.dynamodb` | **없음** — 아래 블록 추가 |
| set-03 | `aws_kms_key.db` | `db_kms_arn` (**이미 있음**) |
| set-07 | `aws_kms_key.app` | `app_kms_arn` (**이미 있음**) |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "dynamodb_kms_arn" { value = aws_kms_key.dynamodb.arn }
```

```powershell
terraform output -raw db_kms_arn        # set-03
terraform output -raw app_kms_arn       # set-07
aws dynamodb describe-table --table-name (terraform output -raw table_name) `
  --query "Table.[DeletionProtectionEnabled,SSEDescription]"
```

**`deletion_protection_enabled = true` 면 `terraform destroy` 가 실패한다** — teardown 전에 false로 apply한다. CMK 전환도 in-place지만 키를 지우면 테이블 접근이 불가해진다.
</details>

## 4. Streams

```hcl
# 파일: set-XX/task-1/terraform/dynamodb.tf
# 기존 aws_dynamodb_table 리소스 블록 *안에* — dynamodb-stream.tf 의 전제
stream_enabled   = true
stream_view_type = "NEW_AND_OLD_IMAGES"   # KEYS_ONLY | NEW_IMAGE | OLD_IMAGE | NEW_AND_OLD_IMAGES
```

<details><summary><b>값 뽑기 — 세트별 (ESM이 stream_arn을 물어본다)</b></summary>

세 세트 모두 Streams가 **꺼져 있다.** 켠 뒤 ARN을 노출한다:

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "table_stream_arn" {
  value = aws_dynamodb_table.data.stream_arn      # set-03 .book / set-07 .concert
}
```

```powershell
terraform output -raw table_stream_arn
aws dynamodb describe-table --table-name (terraform output -raw table_name) `
  --query "Table.StreamSpecification"
```

`stream_view_type` 변경은 스트림이 켜진 상태에서 바로 안 될 수 있다. 실패하면 `stream_enabled = false` 로 한 번 apply한 뒤 새 타입으로 다시 켠다 — **스트림 ARN이 바뀌므로 ESM도 다시 만들어진다.**
</details>

## 5. Streams → Lambda ESM

```hcl
# 파일: set-XX/task-1/terraform/dynamodb-stream.tf   (KIT에서 복사됨)
resource "aws_lambda_event_source_mapping" "addon_ddb" {
  event_source_arn  = aws_dynamodb_table.data.stream_arn        # ← 세트별 주소
  function_name     = aws_lambda_function.book.function_name    # ← 세트별 주소
  starting_position = "LATEST"
  batch_size        = var.addon_ddb_esm_batch_size

  maximum_retry_attempts         = var.addon_ddb_esm_max_retry_attempts
  bisect_batch_on_function_error = var.addon_ddb_esm_bisect_on_error

  depends_on = [aws_iam_role_policy.addon_ddb_stream_read]   # 정책이 먼저 있어야 생성된다
}
```

<details><summary><b>값 뽑기 — 세트별 (Lambda 함수·Role)</b></summary>

| 세트 | Lambda 리소스 | 실행 Role | output |
| --- | --- | --- | --- |
| set-02 | `aws_lambda_function.book` | `aws_iam_role.book_lambda` | **없음** |
| set-03 | `aws_lambda_function.book_get` | `aws_iam_role.book_function` | `lambda_function_url` 만 있음 |
| set-07 | `aws_lambda_function.get_booking` | `aws_iam_role.get_booking` | **없음** |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "lambda_function_name" { value = aws_lambda_function.book.function_name }
output "lambda_role_name"     { value = aws_iam_role.book_lambda.name }
```

```powershell
terraform output -raw lambda_function_name
terraform output -raw lambda_role_name
aws lambda list-event-source-mappings --function-name (terraform output -raw lambda_function_name) `
  --query "EventSourceMappings[].[State,BatchSize,MaximumRetryAttempts,BisectBatchOnFunctionError]"
```

Lambda Role에 `DescribeStream`/`GetRecords`/`GetShardIterator`/`ListStreams` 가 먼저 있어야 ESM이 생성된다. `on_failure` 목적지를 쓰면 그 큐/토픽의 `sqs:SendMessage`/`sns:Publish` 도 Role에 추가한다.
</details>

## 6. GSI 추가

```hcl
# 파일: set-XX/task-1/terraform/dynamodb.tf
# 기존 aws_dynamodb_table 리소스 블록 *안에* — 키 속성을 attribute 로 먼저 선언
attribute {
  name = "client_id"
  type = "S"
}
attribute {
  name = "created_at"
  type = "S"
}

global_secondary_index {
  name            = "client-id-created-at-index"
  hash_key        = "client_id"
  range_key       = "created_at"
  projection_type = "ALL"          # KEYS_ONLY | INCLUDE(non_key_attributes) | ALL
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 이미 있는 GSI | 주의 |
| --- | --- | --- |
| set-02 | `concert_name-created_at-index` (`key_schema` 블록형) | 새 GSI는 `hash_key`/`range_key` 형으로 써도 된다 |
| set-03 | `booking_id-index` (`key_schema` 블록형) | 리소스 정책이 GSI ARN을 명시한다 — 이름을 바꾸면 정책도 같이 고친다 |
| set-07 | `client-id-created-at-index` | 원본에 `// do not change` — 채점이 이 GSI를 검사한다 |

```powershell
aws dynamodb describe-table --table-name (terraform output -raw table_name) `
  --query "Table.GlobalSecondaryIndexes[].[IndexName,IndexStatus]"
```

- **GSI는 한 번의 apply에 1개만 생성/삭제된다** (2개 이상이면 apply 에러). 백필에 수 분 걸리고 그동안 `IndexStatus=CREATING`.
- "GSI 정확히 N개"를 검사하는 테이블에는 추가 GSI를 붙이지 않는다.
</details>

## 7. DynamoDB Gateway 엔드포인트

```hcl
# 파일: set-XX/task-1/terraform/dynamodb-endpoint.tf   (KIT에서 복사됨)
resource "aws_vpc_endpoint" "addon_ddb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for k in local.private_subnet_keys : aws_route_table.private[k].id]   # set-03 은 .app[k]
  tags              = { Name = var.addon_ddb_endpoint_name }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 프라이빗 라우트 테이블 (전부 `for_each` 맵) | 기존 엔드포인트 |
| --- | --- | --- |
| set-02 | `aws_route_table.private[k]` | **없음** |
| set-03 | `aws_route_table.app[k]` | `aws_vpc_endpoint.s3` (S3만) |
| set-07 | `aws_route_table.private[k]` | `aws_vpc_endpoint.s3` + `.interface` |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "private_route_table_ids" {
  value = { for k in local.private_subnet_keys : k => aws_route_table.private[k].id }   # set-03 은 .app[k]
}
output "addon_ddb_endpoint_id" { value = aws_vpc_endpoint.addon_ddb.id }
```

```powershell
terraform output -raw vpc_id                    # 세 세트 모두 이미 있음
terraform output -json private_route_table_ids
aws ec2 describe-vpc-endpoints `
  --filters "Name=service-name,Values=com.amazonaws.ap-northeast-2.dynamodb" `
  --query "VpcEndpoints[].[VpcEndpointType,State,RouteTableIds]"
```

엔드포인트를 여러 개 만들 거면 [vpc-endpoints](../vpc-endpoints/README.md) 쪽이 낫다.
</details>

## VERIFY

```powershell
$t = terraform output -raw table_name
aws dynamodb describe-table --table-name $t `
  --query "Table.[DeletionProtectionEnabled,SSEDescription,StreamSpecification,GlobalSecondaryIndexes[].IndexName]"
aws dynamodb describe-continuous-backups --table-name $t `
  --query "ContinuousBackupsDescription.PointInTimeRecoveryDescription"
aws dynamodb describe-time-to-live --table-name $t
```

## TROUBLESHOOT

- `hash_key`·`range_key`·`name`·`billing_mode` 변경은 **재생성**이다.
- **GSI는 apply 한 번에 1개만.** 백필 중 `IndexStatus=CREATING`.
- ESM 개수를 채점하는 세트에 이 KIT을 겹쳐 붙이면 2개가 되어 실패한다 — 기존 ESM에 인자만 추가한다.
- `maximum_retry_attempts = -1` 은 무제한(레코드 만료 24h까지). `bisect_batch_on_function_error` 는 retry와 독립이며 둘 다 켜면 쪼갠 배치마다 retry가 적용된다.
- `deletion_protection_enabled = true` 면 `terraform destroy` 가 실패한다.
- CMK 전환도 in-place지만 **키를 지우면 테이블 접근이 불가**해진다.
- TTL은 만료 후 최대 48시간 뒤 삭제 — "항목이 사라짐"을 보는 채점은 통과 못 한다.
- 테이블 수준 리소스 정책이 필요하면 **set-03 task-1 `dynamodb.tf`** 의 `aws_dynamodb_resource_policy` 블록을 복사한다.

## 실전 구현 (참고용)

- set-07 task-2 module-1-nosql `terraform/dynamodb.tf`(Streams·GSI·PITR) · `lambda.tf`(스트림 읽기 정책·ESM)
- set-07 task-1 `terraform/dynamodb.tf` (CMK·PITR·삭제 방지·GSI)
- set-03 task-1 `terraform/dynamodb.tf` (PITR 35일·리소스 정책)
