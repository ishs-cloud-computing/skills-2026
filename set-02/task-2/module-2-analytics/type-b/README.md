# Module 2 type-b — Glue 없는 인메모리 카탈로그 + 샤드 정합 병렬도

원본([../README.md](../README.md))의 **대안 구성**이다. 리소스 이름이 원본과 같아 **한 계정에 동시 존재할 수 없다** — 둘 중 하나만 apply 한다.

`terraform/` 은 원본의 전체 복사본이고 아래 5개 파일만 다르다.

| 파일 | 차이 |
|---|---|
| `flink.tf` | `CatalogConfiguration` 제거(인메모리 카탈로그), Glue DB·Glue IAM statement·`time_sleep` 제거, `ParallelismConfiguration` 추가 |
| `variables.tf` | `glue_db_name` 제거, `flink_parallelism`(4)·`flink_parallelism_per_kpu`(1) 추가 |
| `outputs.tf` | `glue_db_name` → `flink_parallelism` |
| `versions.tf` | `time` provider 제거 |
| `data.tf` | `aws_caller_identity` 제거 (Glue ARN 조립 전용이었음) |

나머지 9개(`vpc.tf`·`alb.tf`·`ec2.tf`·`iam.tf`·`kinesis.tf`·`security.tf`·`bastion.tf`·`terraform.tfvars`·`userdata.sh.tpl`)는 원본과 바이트 단위로 같다. **원본의 공통 파일을 고치면 여기도 같이 고친다.**

## 원본과 무엇이 다른가

**1) 노트북 카탈로그가 Glue 가 아니라 Flink 기본 인메모리 카탈로그**

과제지·채점지에 Glue 요구가 없다 — `task.md`·`mark.md`·`mark/mark2-2.sh`·`provided/module2/*`·`errata/*` 전부에서 `glue` 등장 0회. 채점 2-4 의 projection 은 `[ApplicationName, ApplicationStatus, RuntimeEnvironment]` 라 `ApplicationConfiguration` 을 읽지도 않는다. Glue 에 들어가던 것도 데이터가 아니라 `CREATE TABLE`/`CREATE VIEW` 의 DDL 스키마뿐이다 (주문 데이터는 Kinesis, 쿼리 결과는 이미 Flink 인메모리 + Zeppelin 화면 출력).

떼면 원본이 겪던 실패 모드 셋이 같이 사라진다 — IAM 전파 전 `glue:GetDatabase` 검증 실패로 인한 CFN ROLLBACK(원본의 `time_sleep` 30초가 그 우회책), SQL 플래닝 중 `database/hive` AccessDenied(원본이 카탈로그 전체 와일드카드로 우회, 과제지 6 "최소권한" 과 충돌), 재시연 시 stale DDL 충돌(`DROP TABLE` 선행 필요). Flink 역할은 Kinesis 읽기 전용이 된다.

**대가**: 노트북을 중지하면 테이블·뷰 정의가 사라진다. 재시연 시 문단 1 부터 다시 실행한다(문단 텍스트는 노트에 남으므로 ▶ 만 다시 누르면 된다).

**2) 병렬도를 Kinesis 샤드 수에 맞춤 (1 → 4)**

ON_DEMAND 스트림은 초기 4샤드다. parallelism 이 샤드보다 크면 유휴 서브태스크가 생겨 resharding 을 투명하게 처리하지 못하고, 작으면 한 서브태스크가 여러 샤드를 읽는다. 1:1 이 정석이다.

**손잡이가 둘이라 반드시 같이 움직인다** — 앱 레벨 `ParallelismConfiguration`(KPU 할당, `terraform.tfvars` 의 `flink_parallelism`)과 노트북의 `%flink.conf parallelism.default`(실제 잡 병렬도). 앱 레벨만 올리면 자원만 늘고 잡은 그대로다.

과금은 처리 4 KPU + Studio 오버헤드 2 KPU(오케스트레이션 1, 인터랙티브 개발환경 1) = 6 KPU. 원본은 3 KPU.

**속도 기대치**: 이 과제 볼륨(주문 300건)에서는 **체감 차이가 없다.** 병목이 처리량이 아니다. 실익은 속도보다 유휴 서브태스크 없는 정상 구성 쪽이다.

## 배포 순서

원본 런북과 번호가 1:1 대응한다. **아래에 적힌 단계만 다르고, 나머지는 [../README.md](../README.md) 를 그대로 따른다.**

### 1) [본 PC·PowerShell] 배포 — 경로만 다름

```powershell
cd type-b/terraform
terraform init
terraform apply; terraform output -json > outputs.json
```

샤드 수를 바꿔 시험하려면 `terraform apply -var "flink_parallelism=2"` 처럼 준다. **문단 1 의 값도 같이 바꿔야 한다.**

**관문 1** — CFN 스택이 `CREATE_COMPLETE` 여야 한다. `ROLLBACK` 이면 이 구성은 성립하지 않는다:

```powershell
aws cloudformation describe-stacks --stack-name wsc2026-analytics-flink-stack --query "Stacks[0].StackStatus" --output text
```

### 2) [본 PC·PowerShell] 리소스 검증 — 원본과 동일

원본 README 2단계를 그대로 쓴다. 2-4 기대값도 같다 (`wsc2026-analytics-flink  READY  ZEPPELIN-FLINK-3_0`).

병렬도 반영 확인:

```powershell
aws kinesisanalyticsv2 describe-application --application-name wsc2026-analytics-flink --query "ApplicationDetail.ApplicationConfigurationDescription.FlinkApplicationConfigurationDescription.ParallelismConfigurationDescription" --output json
```

샤드 수 확인 (ON_DEMAND 는 자동 증감하므로 시연 직전에 본다):

```powershell
aws kinesis list-shards --stream-name wsc2026-order-stream --query "length(Shards)" --output text
```

### 3)~4) 노트북 실행 · 데이터 주입 — 원본과 동일

### 5) [Zeppelin] 문단 순차 실행 — **문단 1 만 다름**

```
%flink.conf
parallelism.default 4
```

`terraform.tfvars` 의 `flink_parallelism` 과 **같은 값**이어야 한다. `%flink.conf` 는 인터프리터가 뜨기 전에만 먹으므로 반드시 첫 문단이고, 이미 실행된 세션이면 인터프리터를 재시작한 뒤 실행한다.

**관문 2** — 문단 2 의 `CREATE TABLE order_stream_base` / `CREATE VIEW order_stream` 이 통과해야 한다. 여기서 실패하면 인메모리 카탈로그 경로가 성립하지 않는다.

문단 2·3·4 는 원본과 글자 그대로 같다.

### 6) [AWS 콘솔] 시연 후 노트북 중지 — **재개 절차만 다름**

상태가 READY 로 복귀해야 mark 2-4 통과 (**RUNNING 이면 오답**). 인메모리 카탈로그라 중지하면 `order_stream_base`/`order_stream` 정의가 사라진다 — 다시 시연할 때는 문단 1 부터 순서대로 실행한다. 원본과 달리 `DROP TABLE` 선행은 필요 없다.

### 7) [CloudShell] 셀프 채점 — 원본과 동일

## Teardown

```powershell
cd type-b/terraform
terraform destroy
```

## 검증 상태

`terraform fmt` 통과. **`validate`·`plan`·`apply` 미실행** — 관문 1·2 는 실측 전이다.

두 가지가 문서로 확정되지 않아 실측으로만 갈린다:

- **`CatalogConfiguration` 생략**: API 레퍼런스는 `Required: No` 로 명시하지만, 제품 문서·콘솔은 Studio 의 SQL 카탈로그 = Glue 카탈로그를 기본 전제로 서술한다. 생략 경로가 동작한다는 문서·사례는 찾지 못했다.
- **INTERACTIVE 모드의 `FlinkApplicationConfiguration`**: `ParallelismConfiguration` 자체는 CFN 이 지원하지만, Studio(INTERACTIVE) 앱에서 `ZeppelinApplicationConfiguration` 과 함께 받아주는지는 확인하지 못했다. AWS 문서는 Studio 에 "오토스케일링은 적용되지 않는다" 고만 밝힌다.

둘 다 배포 시점에 시끄럽게 실패하므로 채점 당일 조용히 틀리는 종류는 아니다. 실패 시 원본(`../terraform/`)으로 돌아가고, 실패 지점을 `task-2/NOTES.md` 결정 로그에 append 한다.
