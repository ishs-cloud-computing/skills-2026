# dynamodb-hardening 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 DynamoDB 테이블에 TTL·PITR·삭제 방지·CMK·Streams·GSI 를 in-place 로 덧붙이고,
Streams → Lambda ESM 과 Gateway 엔드포인트를 새 리소스로 붙인다.
1과제 Database 옵션(전 세트 task-1 DynamoDB), set-07 m1(Streams→Lambda), set-02 m1/m4, set-05 m4 후보에 대응.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 5개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_ddb_stream_arn` | **필수** | Streams 를 읽을 테이블의 stream_arn. 같은 루트 모듈이면 aws_dynamodb_table.<기존>.stream_arn 으로 바꾼다 |
| `addon_ddb_lambda_function_name` | **필수** | Streams 를 소비할 기존 Lambda 함수 이름 (aws_lambda_function.<기존>.function_name) |
| `addon_ddb_lambda_role_name` | **필수** | 그 Lambda 의 실행 Role 이름 — 스트림 읽기 정책을 여기에 붙인다 (aws_iam_role.<기존>.name) |
| `addon_ddb_vpc_id` | **필수** | 엔드포인트를 붙일 VPC ID (aws_vpc.<기존>.id) |
| `addon_ddb_route_table_ids` | **필수** | 엔드포인트 경로를 넣을 라우트 테이블 ID 목록 (보통 private, aws_route_table.private[*].id) |
| `addon_ddb_esm_batch_size` | `100` | ESM 배치 크기 (Streams 최대 10000) |
| `addon_ddb_esm_max_retry_attempts` | `-1` | 실패 배치 재시도 횟수 (-1 = 무제한, 기본값). 과제지가 '재시도 N회' 를 지정하면 그 값 |
| `addon_ddb_esm_bisect_on_error` | `false` | 함수 오류 시 배치를 반으로 쪼개 재시도 (poison record 격리) |
| `addon_ddb_esm_on_failure_arn` | `""` | 실패 레코드 목적지 SQS/SNS ARN. 빈 문자열이면 destination_config 생략 |
| `addon_ddb_endpoint_name` | `"dynamodb-endpoint"` | 엔드포인트 Name 태그 |

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

- `dynamodb-stream.tf` — 기존 Lambda Role 에 스트림 읽기 정책 + `aws_lambda_event_source_mapping`(batch/retry/bisect/on_failure)
- `dynamodb-endpoint.tf` — `aws_vpc_endpoint` Gateway(dynamodb) + private 라우트 테이블 연결
- `variables.tf` — `addon_ddb_*` 변수. 파일별로 절이 나뉘어 있다 — 쓰는 `.tf` 의 절만 복사한다(다른 절의 필수 변수가 남으면 plan 이 값을 묻는다)

테이블 안에 인자만 추가하는 항목(TTL·PITR·삭제 방지·SSE·Streams·GSI)은 tf 파일 없이 아래 "블록" 을 기존 `aws_dynamodb_table` 에 붙인다.

## 부착 절차

1. 필요한 `.tf` 와 `variables.tf` 의 해당 절을 `set-XX/task-Y/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 같은 루트 모듈의 리소스를 직접 참조하려면 `var.addon_ddb_stream_arn` 을 `aws_dynamodb_table.<기존>.stream_arn` 으로, `var.addon_ddb_vpc_id` 를 `aws_vpc.<기존>.id` 로 바꾼다.

   ```hcl
   # Streams → Lambda
   addon_ddb_stream_arn             = "arn:aws:dynamodb:ap-northeast-2:123456789012:table/skills-table/stream/2026-08-21T00:00:00.000"
   addon_ddb_lambda_function_name   = "skills-audit-func"
   addon_ddb_lambda_role_name       = "skills-audit-func-role"
   addon_ddb_esm_batch_size         = 100
   addon_ddb_esm_max_retry_attempts = 3      # 과제지 "재시도 N회"
   addon_ddb_esm_bisect_on_error    = true
   addon_ddb_esm_on_failure_arn     = ""     # 실패 레코드 SQS/SNS ARN, 없으면 빈 문자열

   # Gateway 엔드포인트
   addon_ddb_vpc_id          = "vpc-0123456789abcdef0"
   addon_ddb_route_table_ids = ["rtb-0123456789abcdef0", "rtb-0123456789abcdef1"]
   addon_ddb_endpoint_name   = "skills-ddb-endpoint"
   ```
3. 기존 테이블 인자 추가는 아래 "블록" 을 `aws_dynamodb_table.<기존>` 안에 붙인다.
4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스가 `update in-place` 만 뜨는지(`replace` 없음) 확인 → `terraform apply`.
5. 검증:

   ```powershell
   aws dynamodb describe-table --table-name <테이블> --query 'Table.[DeletionProtectionEnabled,SSEDescription,StreamSpecification,GlobalSecondaryIndexes[].IndexName]'
   aws dynamodb describe-continuous-backups --table-name <테이블> --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription'
   aws dynamodb describe-time-to-live --table-name <테이블>
   aws lambda list-event-source-mappings --function-name <함수> --query 'EventSourceMappings[].[State,BatchSize,MaximumRetryAttempts,BisectBatchOnFunctionError]'
   aws ec2 describe-vpc-endpoints --filters Name=service-name,Values=com.amazonaws.<리전>.dynamodb --query 'VpcEndpoints[].[VpcEndpointType,State,RouteTableIds]'
   ```

## 블록

전부 `aws_dynamodb_table.<기존>` 리소스 안에 넣는다. 모두 in-place 다.

```hcl
# aws_dynamodb_table 리소스 안에: TTL (속성값은 epoch 초 Number)
ttl {
  attribute_name = "expires_at"
  enabled        = true
}
```

```hcl
# aws_dynamodb_table 리소스 안에: PITR (recovery_period_in_days 1~35, 과제지 "최장" 이면 35)
point_in_time_recovery {
  enabled                 = true
  recovery_period_in_days = 35
}
```

```hcl
# aws_dynamodb_table 리소스 안에: 삭제 방지
deletion_protection_enabled = true
```

```hcl
# aws_dynamodb_table 리소스 안에: CMK 암호화 (kms 키트와 조합)
server_side_encryption {
  enabled     = true
  kms_key_arn = aws_kms_key.addon.arn
}
```

```hcl
# aws_dynamodb_table 리소스 안에: Streams (dynamodb-stream.tf 의 전제)
stream_enabled   = true
stream_view_type = "NEW_AND_OLD_IMAGES" # KEYS_ONLY | NEW_IMAGE | OLD_IMAGE | NEW_AND_OLD_IMAGES
```

```hcl
# aws_dynamodb_table 리소스 안에: GSI 추가 (키 속성은 attribute 로 먼저 선언)
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
  projection_type = "ALL" # KEYS_ONLY | INCLUDE(non_key_attributes) | ALL
}
```

## TROUBLESHOOT — 이 KIT 고유 함정
- 위 블록은 전부 in-place. 단 `hash_key`·`range_key`·`name`·`billing_mode` 를 건드리면 ⚠ 재생성 — 손대지 않는다.
- **GSI 는 한 번의 apply 에 1개만 생성/삭제**된다(2개 이상이면 apply 에러). 백필에 수 분 걸리고 그동안 `IndexStatus=CREATING`. set-07 m1 채점 1-2-A 처럼 "GSI 정확히 N개" 를 검사하는 테이블에는 추가 GSI 를 붙이지 않는다.
- `stream_view_type` 변경은 스트림이 켜진 상태에서 바로 안 된다 — 확인 필요: 실패하면 `stream_enabled = false` apply 후 새 타입으로 다시 켠다. 스트림 ARN 이 바뀌므로 ESM 도 다시 만들어진다.
- ESM 은 Lambda Role 에 `DescribeStream/GetRecords/GetShardIterator/ListStreams` 가 먼저 있어야 생성된다(스니펫이 `depends_on` 으로 강제). `on_failure` 목적지를 쓰면 그 큐/토픽에 `sqs:SendMessage`/`sns:Publish` 도 Role 에 추가한다.
- ESM 개수를 채점하는 세트(set-07 m1 1-3-A: 정확히 1개 `Enabled`)에 이 스니펫을 겹쳐 붙이면 2개가 되어 실패 — 기존 ESM 에 `batch_size` 등 인자만 추가한다.
- `maximum_retry_attempts = -1` 은 무제한(레코드 만료 24h 까지). 과제지가 횟수를 주면 그 값. `bisect_batch_on_function_error` 는 retry 와 독립이며 둘 다 켜면 쪼갠 배치마다 retry 가 적용된다.
- `deletion_protection_enabled = true` 면 `terraform destroy` 가 실패한다 — teardown 전에 false 로 apply.
- `server_side_encryption { enabled = true }` 만 쓰면 AWS 관리 키(`aws/dynamodb`), `enabled = false` 는 AWS 소유 키. CMK 는 `kms_key_arn` 필수. CMK 전환도 in-place 이나 키를 지우면 테이블 접근 불가.
- TTL 은 만료 후 최대 48시간 뒤 삭제된다 — 채점이 "항목 사라짐" 을 보면 통과 불가, 보통 `TimeToLiveStatus=ENABLED` + 속성명만 본다. 속성값이 문자열이면 만료되지 않는다.
- Gateway 엔드포인트는 **`route_table_ids` 에 넣은 테이블만** 경로를 받는다. 앱 서브넷(EKS 노드·ECS 태스크·Lambda)이 쓰는 라우트 테이블을 빠짐없이 넣는다. SG·서브넷 인자 없음(Interface 와 다름). 테이블 리전 ≠ VPC 리전이면 경로만 생기고 쓸모없다. 채점은 `VpcEndpointType=Gateway` + `ServiceName=com.amazonaws.<리전>.dynamodb` 를 본다(set-08 task-1 1-5).
- 테이블 수준 리소스 정책(`aws_dynamodb_resource_policy`)이 필요하면 set-03 task-1 `dynamodb.tf` 의 블록을 복사한다.

## 실전 구현 (참고용)

- set-07 task-2 module-1-nosql `terraform/dynamodb.tf`(Streams·GSI·PITR)·`lambda.tf`(스트림 읽기 정책·ESM)
- set-07 task-1 `terraform/dynamodb.tf`(CMK·PITR·삭제 방지·GSI), set-03 task-1 `terraform/dynamodb.tf`(PITR 35일·리소스 정책)
- set-08 task-1 `terraform/vpc.tf`(Gateway 엔드포인트)
