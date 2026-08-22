# msk-hardening 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 `aws_msk_cluster` 에 브로커 로그·모니터링·암호화·server.properties·Lambda 트리거를 얹는다.
2과제 MSK 모듈(set-02 task-2 module-4-msk) 의 당일 추가 문항("브로커 로그를 CloudWatch 로",
"Prometheus 모니터링 활성화", "CMK 암호화", "auto.create.topics 비활성", "Lambda 로 토픽 소비") 에 대응한다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 0개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_msk_cluster_name` | `"wsc2026-msk-cluster"` | 기존 MSK 클러스터 이름. 로그 그룹·configuration 이름 접두로 쓴다 |
| `addon_msk_log_group_name` | `"/aws/msk/wsc2026-msk-cluster"` | 브로커 로그 그룹 이름. 과제지 명시값이 있으면 정확히 일치시킨다 |
| `addon_msk_log_retention_days` | `7` | 브로커 로그 보존 일수 |
| `addon_msk_configuration_name` | `"wsc2026-msk-config"` | MSK configuration 이름. 과제지 명시값이 있으면 정확히 일치시킨다 |
| `addon_msk_kafka_versions` | `["3.6.0"]` | configuration 이 적용 가능한 Kafka 버전 목록. 기존 클러스터 kafka_version 을 반드시 포함 |
| `addon_msk_server_properties` | `<<-EOT` | server.properties 본문. 과제지가 요구한 키만 넣는다 (auto.create.topics.enable 등) |
| `addon_msk_cluster_arn` | `""` | ESM 을 붙일 기존 MSK 클러스터 ARN. 같은 state 면 aws_msk_cluster.<기존>.arn 으로 바꾼다 |
| `addon_msk_esm_function_name` | `""` | MSK 토픽을 소비할 기존 Lambda 함수 이름. 빈 문자열이면 ESM·정책을 만들지 않는다 |
| `addon_msk_esm_lambda_role_name` | `""` | 위 Lambda 의 실행 역할 이름 (ESM 폴러 정책·kafka-cluster 데이터 액션을 붙인다) |
| `addon_msk_esm_topics` | `["wsc2026-sensor-raw"]` | ESM 이 소비할 토픽 이름 목록 |
| `addon_msk_esm_batch_size` | `100` | ESM 배치 크기 |

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

- `msk-hardening.tf` — 브로커 로그 그룹 · `aws_msk_configuration` · Lambda ESM(MSK) + 실행 역할 정책 (ESM 은 `addon_msk_esm_function_name` 이 비어 있으면 생성 안 함)
- `variables.tf` — `addon_msk_*` 변수. 클러스터 ARN·Lambda 이름·역할 이름은 변수로 받는다

`aws_msk_cluster` **안에** 넣는 인자(로그·모니터링·암호화·configuration 연결)는 아래 "블록" 절을 기존 `msk.tf` 에 붙여 넣는다.

## 부착 절차

1. `msk-hardening.tf`·`variables.tf` 를 `set-XX/task-2/module-N-msk/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 같은 state 의 클러스터를 직접 참조하려면 `var.addon_msk_cluster_arn` 을 `aws_msk_cluster.this.arn` 으로 바꾼다.

   ```hcl
   addon_msk_cluster_name       = "wsc2026-msk-cluster"
   addon_msk_log_group_name     = "/aws/msk/wsc2026-msk-cluster"
   addon_msk_configuration_name = "wsc2026-msk-config"
   addon_msk_kafka_versions     = ["3.6.0"]              # 기존 kafka_version 포함 필수
   addon_msk_server_properties  = <<-EOT
     auto.create.topics.enable=false
     default.replication.factor=3
     min.insync.replicas=2
   EOT
   # Lambda 트리거가 요구될 때만
   addon_msk_cluster_arn          = "arn:aws:kafka:ap-northeast-1:123456789012:cluster/wsc2026-msk-cluster/..."
   addon_msk_esm_function_name    = "wsc2026-sensor-consumer"
   addon_msk_esm_lambda_role_name = "wsc2026-msk-lambda-role"
   addon_msk_esm_topics           = ["wsc2026-sensor-raw"]
   ```

3. 아래 "블록" 중 과제지가 요구한 것만 기존 `aws_msk_cluster` 리소스 안에 추가한다.
4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 클러스터가 **update in-place** 인지 확인한다 (`must be replaced` 가 보이면 함정 절 확인).
5. `terraform apply`. MSK 업데이트는 항목당 10~30분이며 한 번에 하나만 진행된다 — 블록을 **한 번의 apply 에 모두** 넣는다.

## 블록

### 브로커 로그 — CloudWatch Logs (in-place)

```hcl
# aws_msk_cluster 리소스 안에:
logging_info {
  broker_logs {
    cloudwatch_logs {
      enabled   = true
      log_group = aws_cloudwatch_log_group.addon_msk_broker.name
    }
  }
}
```

### 브로커 로그 — S3 (in-place, 기존 버킷 필요)

```hcl
# aws_msk_cluster 리소스 안에 (cloudwatch_logs 와 같은 broker_logs 블록에 나란히 둘 수 있다):
logging_info {
  broker_logs {
    s3 {
      enabled = true
      bucket  = aws_s3_bucket.<기존>.id
      prefix  = "msk-broker-logs/"
    }
  }
}
```

### 모니터링 수준 (in-place)

```hcl
# aws_msk_cluster 리소스 안에:
enhanced_monitoring = "PER_TOPIC_PER_BROKER"   # DEFAULT | PER_BROKER | PER_TOPIC_PER_BROKER | PER_TOPIC_PER_PARTITION
```

### Open Monitoring — Prometheus exporter (in-place)

```hcl
# aws_msk_cluster 리소스 안에:
open_monitoring {
  prometheus {
    jmx_exporter {
      enabled_in_broker = true
    }
    node_exporter {
      enabled_in_broker = true
    }
  }
}
```

수집기가 브로커 11001(JMX)·11002(Node) 포트에 붙어야 하므로 MSK SG 에 해당 포트 ingress 를 연다.

### server.properties 연결 (in-place)

```hcl
# aws_msk_cluster 리소스 안에:
configuration_info {
  arn      = aws_msk_configuration.addon.arn
  revision = aws_msk_configuration.addon.latest_revision
}
```

### 저장 데이터 CMK 암호화 (⚠ 재생성)

```hcl
# aws_msk_cluster 리소스 안의 encryption_info 블록에:
encryption_info {
  encryption_at_rest_kms_key_arn = var.addon_kms_key_arn   # kms/ 스니펫의 aws_kms_key.addon.arn
  encryption_in_transit {
    client_broker = "TLS"
    in_cluster    = true
  }
}
```

### 브로커 3대 / 3AZ

- 신규 클러스터: 프라이빗 서브넷 3개(서로 다른 AZ) 를 `client_subnets` 에 넣고 `number_of_broker_nodes = 3`. 브로커 수는 서브넷 수의 배수여야 한다.
- 기존 2AZ 클러스터: `number_of_broker_nodes` 만 올리는 건 in-place 지만 **2의 배수(4)** 만 가능하다. 3대를 만들려면 `client_subnets` 를 바꿔야 하고 이는 ⚠ 재생성이다.
- set-02 m4 는 ap-northeast-1 a/d 2AZ 구성 — 3AZ 로 가려면 `msk-priv-c` 서브넷을 추가한다(1b 는 신규 계정에서 사용 불가).

### Lambda ESM

`msk-hardening.tf` 의 `aws_lambda_event_source_mapping.addon_msk` 가 만든다. 함수가 VPC 밖이어도 ESM 폴러는 클러스터 쪽에서 돌므로 함수 `vpc_config` 는 불필요하다 (함수가 토픽에 **produce** 도 하면 VPC 안 + 9098 SG 필요).

## TROUBLESHOOT — 이 KIT 고유 함정
- **재생성 유발**: `encryption_at_rest_kms_key_arn`, `client_subnets`(AZ 변경), `cluster_name`. 나머지(로그·모니터링·configuration·브로커 수 증설·인스턴스 타입·kafka_version) 는 in-place.
- MSK 는 클러스터가 ACTIVE 일 때만 업데이트를 받는다. 여러 항목을 따로 apply 하면 두 번째부터 `BadRequestException: cluster is not ACTIVE` — 한 번에 넣고 기다린다.
- `aws_msk_configuration.kafka_versions` 에 기존 클러스터 `kafka_version` 이 없으면 `configuration_info` 연결이 거부된다.
- `default.replication.factor` 는 브로커 수 이하여야 한다. 브로커 2대에 3 을 넣으면 토픽 생성이 실패한다 — 기존 토픽에는 영향 없음(신규 토픽만).
- `auto.create.topics.enable=false` 로 바꾸면 토픽을 미리 만들지 않은 producer 가 실패한다. 기존 채점 항목(토픽 존재 확인)과 충돌하지 않는지 먼저 본다.
- ESM 은 실행 역할에 `AWSLambdaMSKExecutionRole` + `kafka-cluster:Connect/DescribeTopic/ReadData/DescribeGroup/AlterGroup` 이 없으면 PROBLEM 상태로 멈추고 에러를 내지 않는다. 스니펫이 둘 다 붙인다.
- 로그 그룹 이름·configuration 이름·enhanced_monitoring 값은 채점 스크립트가 describe-cluster 로 직접 읽는 값이다. tfvars 로만 바꾼다.
- S3 브로커 로그는 버킷이 같은 리전에 있어야 한다.

## 실전 구현 (참고용)

- `set-02/task-2/module-4-msk/terraform/msk.tf` — 클러스터 본체 (IAM 인증·TLS)
- `set-02/task-2/module-4-msk/terraform/lambda.tf` — Lambda 2개 + MSK ESM
- `set-02/task-2/module-4-msk/terraform/iam.tf` — ESM 폴러·kafka-cluster 데이터 액션 정책
