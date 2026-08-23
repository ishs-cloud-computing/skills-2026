# kinesis-firehose 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 Kinesis Data Stream 에 Firehose → S3 적재를 붙이고, 스트림 자체의 하드닝(KMS·보존·용량 모드)
과 Lambda 트리거를 추가한다. 2과제 분석 모듈(set-02 task-2 module-2-analytics) 의 당일 추가 문항
("스트림 데이터를 S3 에 보관", "스트림 암호화·보존 기간", "Lambda 로 소비") 에 대응한다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 1개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_firehose_stream_arn` | **필수** | 소스 Kinesis Data Stream ARN (기존 리소스). 같은 state 면 aws_kinesis_stream.<기존>.arn 으로 바꾼다 |
| `addon_firehose_name` | `"wsc2026-orders-firehose"` | Firehose 전송 스트림 이름. 과제지 명시 이름과 정확히 일치시킨다 |
| `addon_firehose_stream_kms_key_arn` | `""` | 소스 스트림이 CMK 로 암호화돼 있으면 그 키 ARN (역할에 kms:Decrypt 부여). AWS 관리 키(alias/aws/kinesis)·미암호화면 빈 문자열 |
| `addon_firehose_bucket_name` | `"wsc2026-orders-archive-000"` | 적재 대상 S3 버킷 이름 (새로 만든다). 전역 유일 — 비번호 등 접미사 포함 |
| `addon_firehose_prefix` | `"orders/!{timestamp:yyyy/MM/dd/HH}/"` | S3 객체 접두사. 과제지가 파티션 형식을 지정하면 그대로 넣는다 |
| `addon_firehose_error_prefix` | `"errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"` | 변환·전송 실패 객체 접두사. !{firehose:error-output-type} 포함 필수 |
| `addon_firehose_buffer_mb` | `5` | 버퍼 크기(MiB) 1~128 |
| `addon_firehose_buffer_sec` | `60` | 버퍼 간격(초) 0~900. 채점 중 빨리 보이려면 60 |
| `addon_firehose_compression` | `"UNCOMPRESSED"` | S3 압축 형식: UNCOMPRESSED &#124; GZIP &#124; ZIP &#124; Snappy &#124; HADOOP_SNAPPY |
| `addon_firehose_role_name` | `"wsc2026-firehose-role"` | Firehose 서비스 역할 이름 |
| `addon_firehose_log_retention_days` | `7` | Firehose 오류 로그 그룹 보존 일수 |
| `addon_firehose_esm_function_name` | `""` | 스트림을 소비할 기존 Lambda 함수 이름. 빈 문자열이면 ESM·정책을 만들지 않는다 |
| `addon_firehose_esm_lambda_role_name` | `""` | 위 Lambda 의 실행 역할 이름 (AWSLambdaKinesisExecutionRole 을 붙인다) |
| `addon_firehose_esm_batch_size` | `100` | ESM 배치 크기 |
| `addon_firehose_esm_starting_position` | `"LATEST"` | ESM 시작 위치: LATEST &#124; TRIM_HORIZON |

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

- `kinesis-firehose.tf` — S3 버킷 · Firehose 서비스 역할 · 오류 로그 그룹 · `aws_kinesis_firehose_delivery_stream`(kinesis_source → extended_s3) · Lambda ESM(Kinesis) (`addon_firehose_esm_function_name` 이 비어 있으면 생성 안 함)
- `variables.tf` — `addon_firehose_*` 변수. 소스 스트림 ARN·Lambda 이름·역할 이름은 변수로 받는다

`aws_kinesis_stream` **안에** 넣는 인자는 아래 "블록" 절을 기존 `kinesis.tf` 에 붙여 넣는다.

## 부착 절차

1. `kinesis-firehose.tf`·`variables.tf` 를 `set-XX/task-2/module-N-analytics/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 같은 state 의 스트림을 직접 참조하려면 `var.addon_firehose_stream_arn` 을 `aws_kinesis_stream.orders.arn` 으로 바꾼다.

   ```hcl
   addon_firehose_name        = "wsc2026-orders-firehose"
   addon_firehose_stream_arn  = "arn:aws:kinesis:ap-northeast-2:123456789012:stream/wsc2026-orders"
   addon_firehose_bucket_name = "wsc2026-orders-archive-103"   # 비번호 접미사
   addon_firehose_prefix      = "orders/!{timestamp:yyyy/MM/dd/HH}/"
   addon_firehose_buffer_sec  = 60
   # Lambda 트리거가 요구될 때만
   addon_firehose_esm_function_name    = "wsc2026-order-consumer"
   addon_firehose_esm_lambda_role_name = "wsc2026-order-lambda-role"
   ```

3. 스트림 하드닝이 요구되면 아래 "블록" 을 기존 `aws_kinesis_stream` 안에 추가한다.
4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스가 **update in-place** 또는 no-op 인지 확인한다.
5. `terraform apply`. 확인: `aws firehose describe-delivery-stream --delivery-stream-name <이름> --query DeliveryStreamDescription.DeliveryStreamStatus` 가 `ACTIVE`, 버퍼 간격 뒤 `aws s3 ls s3://<버킷>/orders/ --recursive`.

## 블록

### 스트림 하드닝 (전부 in-place)

```hcl
# aws_kinesis_stream 리소스 안에:
encryption_type  = "KMS"
kms_key_id       = "alias/aws/kinesis"   # CMK 요구 시 kms/ 스니펫의 aws_kms_key.addon.arn
retention_period = 48                    # 시간. 24~8760

# 용량 모드 — 둘 중 하나만
stream_mode_details {
  stream_mode = "ON_DEMAND"
}
# 또는 프로비저닝:
# shard_count = 2
# stream_mode_details {
#   stream_mode = "PROVISIONED"
# }
```

### Lambda ESM (Kinesis)

`kinesis-firehose.tf` 의 `aws_lambda_event_source_mapping.addon_kinesis` 가 만든다. 실패 레코드 격리·재시도 제한이 요구되면 ESM 에 추가한다:

```hcl
# aws_lambda_event_source_mapping 리소스 안에:
maximum_retry_attempts             = 3
bisect_batch_on_function_error     = true
maximum_batching_window_in_seconds = 5
```

### Managed Flink (안내만)

Flink 애플리케이션(Studio Notebook) 은 `aws_kinesisanalyticsv2_application` 이 Zeppelin 블록을 지원하지 않아
CloudFormation 스택으로 래핑한다 — `set-02/task-2/module-2-analytics/terraform/flink.tf` 를 그대로 쓴다.
노트북을 스트리밍 애플리케이션으로 배포(`DeployAsApplicationConfiguration { S3ContentLocation { BucketARN, BasePath } }`)하라는
문항이면 그 CFN 템플릿의 `ZeppelinApplicationConfiguration` 안에 추가한다 — **확인 필요**(저장소 실측 없음, CFN 문서 기준).

## TROUBLESHOOT — 이 KIT 고유 함정
- **재생성 없음**: 스트림의 `encryption_type`·`kms_key_id`·`retention_period`·`shard_count`·`stream_mode_details` 는 전부 in-place. 단 용량 모드 전환은 24시간에 2회만 허용.
- ON_DEMAND 스트림에 `shard_count` 를 넣으면 plan 에서 충돌 — 프로비저닝 전환 시에만 같이 넣는다.
- Firehose 역할은 `sts:ExternalId = 계정 ID` 조건이 걸려 있다(서비스 혼동 대리인 방지). 다른 계정 스트림은 대상 아님.
- 소스 스트림이 CMK 로 암호화돼 있으면 `addon_firehose_stream_kms_key_arn` 을 넣어야 한다 — 없으면 전송 스트림은 ACTIVE 인데 S3 에 아무것도 안 쌓이고 오류 로그에만 AccessDenied 가 남는다.
- `error_output_prefix` 에 `!{firehose:error-output-type}` 이 없으면 생성이 거부된다.
- `buffering_interval` 기본 300초 — 채점 직전 apply 면 객체가 아직 없을 수 있다. 60초로 두고 채점 전 데이터를 한 번 흘린다.
- 전송 스트림 이름·버킷 이름은 채점 스크립트가 describe-delivery-stream 으로 읽는 값이다. tfvars 로만 바꾼다.
- ESM 은 Lambda 역할에 `AWSLambdaKinesisExecutionRole` 이 없으면 생성이 실패한다. 스니펫이 붙인다. ESM 과 Firehose 는 같은 스트림을 동시에 읽어도 된다(샤드당 읽기 한도 2 MB/s 공유).
- Flink(Studio) 는 mark 가 `READY` 상태를 기대했다(set-02 2-4) — 자동 시작 금지.

## 실전 구현 (참고용)

- `set-02/task-2/module-2-analytics/terraform/kinesis.tf` — ON_DEMAND 스트림
- `set-02/task-2/module-2-analytics/terraform/flink.tf` — Managed Flink Studio (CFN 래핑)
- `set-02/task-2/module-3-msk/terraform/lambda.tf` — Lambda ESM 패턴
- Firehose 실전 구현: 없음
