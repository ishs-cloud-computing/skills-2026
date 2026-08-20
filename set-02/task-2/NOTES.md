# set-02 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 기본 4개. 당일 최대 6개까지 늘 수 있다. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 리전 | 미해결 |
|------|------|------|--------|
| 1 | workflow | ap-southeast-1 | 없음 |
| 2 | analytics | ap-northeast-2 | 원본(`terraform/`) 실배포 검증 완료. 대안 `type-b/`(Glue 없는 인메모리 카탈로그 + 병렬도 4) 실배포 미검증 — 관문 둘은 CFN `CREATE_COMPLETE` 와 문단 2 `CREATE TABLE`. 리소스 이름이 같아 둘 중 하나만 apply |
| 3 | event | eu-west-1 | 없음 |
| 4 | msk | ap-northeast-1 | iam(기본) 실배포 검증 2026-08-16. tls(`-var` 지정) 실배포 미검증. 당일 모드는 `select-auth-mode` 판정을 따른다 |

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

### module-4 (2026-08-16 실 apply, `producer_auth_mode=iam`)

- apply 전체: 50 리소스 / **35분 17초** (22:15:42 → 22:50:59)
- `aws_msk_cluster`: **31분 40초** — 전체의 90%. 나머지는 NAT GW 1분 55초,
  sensor_consumer(VPC 배치라 ENI) 2분 7초, ESM sensor 55초 / alert 2분 37초
- producer systemd `app` active: 22:49:11 — apply 종료 **1분 48초 전**. user_data 의
  kafka 다운로드·토픽 생성·S3 바이너리 수신이 MSK ACTIVE 직후 다 끝난다
- 첫 DynamoDB 레코드 22:50:56 / 첫 S3 `alert/` 객체 22:51:03 — **apply 종료 시점에 이미 흐른다**.
  기존 런북의 "3~5분 대기" 는 근거 없는 과대 대기였고, 폴링 루프는 1회에 통과한다
- 가동 20분 시점: DynamoDB 327건, `alert/` 객체 32개 (발행 간격 약 8초, 이상치 비율 ~10%)
- `terraform destroy`: 50 리소스 / **23분 5초** (23:13:58 → 23:37:03), 수동 개입 없이 1회 완료.
  MSK 클러스터 삭제가 대부분이다 — 리허설 종료 시각을 잡을 때 이 23분을 빼고 계산한다
- 단, **private 서브넷(`msk-priv-a`/`msk-priv-d`)과 `msk-vpc` 삭제에서 데드락**이 걸리는 경우가 있다.
  VPC Lambda(sensor_consumer)·MSK ESM 의 Hyperplane ENI 가 terraform state 밖이라 회수가 늦고,
  그 ENI 가 서브넷을 잡고 있어 `DependencyViolation` 이 난다. 5~10분 뒤 destroy 재실행으로 대개
  풀리고, 안 풀리면 VPC 잔여 ENI 를 detach/delete 로 수동 정리한다(런북 Teardown 절)

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

### 2026-08-20 [module-2] Glue 없는 대안 구성을 type-b/ 로 분리 (원본은 그대로 유지)
- 맥락: `flink.tf` 가 `aws_glue_catalog_database` 를 만들어 CFN 의 `ZeppelinApplicationConfiguration.CatalogConfiguration` 에 물려 쓰는데, Glue 는 **과제 요구가 아니다** — `task.md`·`mark.md`·`mark/mark2-2.sh`·`provided/module2/*`·`errata/*` 전부에서 `glue` 등장 0회. 채점 2-4 의 projection 이 `[ApplicationName, ApplicationStatus, RuntimeEnvironment]` 라 `ApplicationConfiguration` 을 읽지도 않는다. Glue 에 들어가던 것도 데이터가 아니라 `CREATE TABLE`/`CREATE VIEW` 의 DDL 스키마뿐이었다(주문 데이터는 Kinesis, 쿼리 결과는 이미 Flink 인메모리 + Zeppelin 화면 출력). 또 병렬도가 `parallelism.default 1` 로 고정돼 있는데 ON_DEMAND 스트림은 초기 4샤드라 1:1 이 아니었다
- 채택: **원본 `terraform/` 은 손대지 않고** `type-b/terraform/` 에 전체 복사본을 두고 거기서만 바꿨다. (1) `CatalogConfiguration` 을 빼 Flink 기본 인메모리 카탈로그를 쓰게 하고 딸린 것들(Glue DB, `GlueCatalog` IAM statement, `time_sleep`, `glue_db_name`, `time` provider, Glue ARN 전용이던 `data.aws_caller_identity`)을 제거. (2) `FlinkApplicationConfiguration.ParallelismConfiguration` 으로 `Parallelism=4`, `ParallelismPerKPU=1` 을 주고 type-b README 문단 1 을 `parallelism.default 4` 로 맞췄다. 원본 대비 실제로 다른 파일은 `flink.tf`·`variables.tf`·`outputs.tf`·`versions.tf`·`data.tf` 5개뿐이고 나머지 9개는 바이트 동일
- 근거: Glue 제거로 **이 저장소가 실측한 실패 모드 3개가 함께 사라진다.** (1) KinesisAnalyticsV2 가 스택 생성 시 role 로 `glue:GetDatabase` 를 동기 호출해 검증하는데 IAM 전파 전이면 CFN ROLLBACK — 원본의 30초 `time_sleep` 은 보장이 아니라 타이밍 땜질이다. (2) Glue IAM 을 analytics DB 로만 스코프했더니 Zeppelin 이 SQL 플래닝 때 `hive`/`default` 를 탐침해 `database/hive` 에서 AccessDenied — 카탈로그 전체 와일드카드로 넓혀 우회한 상태였고 과제지 6 "IAM Role에는 최소권한이 적용되어야 합니다" 와 충돌했다. type-b 는 Kinesis 읽기 전용이다. (3) Glue 영속성 탓에 재시연 시 stale DDL 이 충돌해 `DROP TABLE order_stream;` 선행이 필요했다. 병렬도 쪽은 Flink 공식 문서 근거 — parallelism 이 샤드보다 크면 유휴 서브태스크가 생기고 그 상태에서는 resharding 을 투명하게 처리하지 못한다
- 기각: (1) **원본을 제자리에서 고치기** — 한 번 그렇게 커밋했다가 revert 했다. 원본은 실배포로 검증된 유일한 구성이고 type-b 의 두 변경 모두 미검증이라, 검증된 쪽을 덮으면 대회 당일 물러설 자리가 없어진다. (2) **폴더 대신 변수 플래그**(`catalog_mode = glue | memory`, module-4 의 `producer_auth_mode` 선례) — 중복은 없지만 한 파일에 두 경로가 섞여 원본이 "그대로 보존" 되지 않는다. (3) 유지 근거로 검토했다가 접은 것 둘: "인터프리터 재시작마다 DDL 재입력" 은 과장이다(Zeppelin 문단 텍스트는 노트에 저장되므로 ▶ 한 번 더가 전부), "30% 변동으로 S3 싱크 추가 대비" 도 약하다(`CREATE TABLE ... WITH ('connector'='filesystem')` 은 인메모리 카탈로그에서도 되고 Glue 는 정의의 영속화에만 관여한다)
- 대가: **두 변경 다 미검증이고 실측 관문이 둘이다.** (1) CFN 스택이 `CREATE_COMPLETE` 되는가 — `CatalogConfiguration` 생략은 API 레퍼런스상 `Required: No` 지만 제품 문서·콘솔은 Glue 카탈로그를 Studio 의 SQL 카탈로그로 전제해 서술하고, 생략 사례를 찾지 못했다. INTERACTIVE 앱이 `ZeppelinApplicationConfiguration` 과 `FlinkApplicationConfiguration` 을 함께 받아주는지도 확인 못 했다(AWS 문서는 Studio 에 오토스케일링이 적용되지 않는다고만 밝힌다). (2) 문단 2 의 `CREATE TABLE` 이 통과하는가. 둘 다 배포 시점에 시끄럽게 실패하므로 채점 당일 조용히 틀리는 종류는 아니고, 실패하면 원본으로 돌아가면 된다. 그 외 상시 대가: type-b 는 노트북 중지 시 DDL 소실, KPU 과금 3→6(처리 4 + Studio 오버헤드 2), 공통 9개 파일이 원본과 중복이라 공통 값이 바뀌면 두 곳을 고쳐야 한다
- 속도 기대치: 병렬도 4 는 이 과제 볼륨(주문 300건)에서 **체감 차이를 만들지 않는다.** 병목이 처리량이 아니다. 실익은 유휴 서브태스크 없는 정상 구성 쪽이지 속도가 아니다
- 미확인: `terraform fmt` 까지만 통과했다. `validate`·`plan`·`apply` 미실행 (작업 환경에서 registry.terraform.io 가 막혀 provider 설치 불가). 본 PC 에서 관문 1·2 를 확인할 것

### 2026-08-17 [module-4] 두 경로 설명을 README 한 절로 통합 + "당일 제출은 tls" 확정 서술 철회
- 맥락: 같은 날 앞선 결정으로 두 경로 설명이 6곳(README 최상단 표 + A/B 절, app/README, BINARY-ANALYSIS, terraform.tfvars 주석, variables.tf 주석)에 중복 서술됐다. 값 하나가 바뀔 때 고칠 자리가 6곳이라 대회 중 정정이 서로 어긋날 위험이 크다. 게다가 그 서술들이 **"대회 당일 제출은 tls 다"를 확정 사실로** 적고 있었다
- 채택 1(중복 제거): README.md "producer 인증 경로" 절의 **비교표 하나를 단일 출처**로 두고(apply 명령·바이너리·포트·클러스터 설정·엔드포인트·과제지 충족 여부·쓰는 때를 열로), 나머지 5곳은 그 절로 링크만 남겼다. A/B 두 절 구성은 표로 접었다 — 순서·검증이 동일한 두 경로라 병렬 비교가 산문보다 빠르다
- 채택 2(확정 서술 철회): 모드는 문서가 정하는 게 아니라 **그날 지급된 제공 바이너리를 `check-binary-auth` 로 검사한 결과가 정한다**. 리버싱 결론은 "2026-08-17 배포본 기준"으로 시점을 명시하고, 모든 문서가 판정을 `select-auth-mode` 출력에 위임하도록 문구를 바꿨다. 출제 측이 바이너리를 교체하면 tls 전제가 통째로 틀리는데, 그때 문서만 믿으면 과제지 요구를 만족하는 iam 경로를 두고도 우회로 내려간다
- 남긴 예외: BINARY-ANALYSIS 의 "tls 경로에 9098 을 주면 `unexpected EOF`" 복구 절차는 리버싱 결과(`main.tlsConfigFor` 가 9094 에서만 TLS)에 직접 매달린 내용이라 그 문서에 유일본으로 둔다
- 대가: 대회 중 README 를 못 여는 상황이면 tfvars·variables.tf 주석만으로는 경로 차이를 알 수 없다. 대신 `select-auth-mode` 출력이 쓸 모드와 apply 명령을 그대로 찍으므로 판단 자체엔 README 가 필요 없다

### 2026-08-17 [module-4] 정통(iam)·대회 제출 우회(tls) 두 경로를 문서상 분리, 기본값은 iam 유지
- 맥락: 2026-08-16 결정(iam 기본)에 빠진 전제가 하나 있었다 — **대회는 제공 바이너리(`provided/module4/app`) 외 배포를 허용하지 않는다.** 자체 제작 `app/producer` 를 대회 당일 EC2 에 올리는 경로 자체가 없으므로, 대회 당일 실제 제출은 tls 우회로 갈 수밖에 없다. 그런데 런북은 iam 만 다루고 tls 절차를 뺐던 상태라 대회 당일 쓸 문서가 없었다
- 채택: 기본값은 `iam`(정통 — 과제지 요구를 실제로 만족) 유지, 대회 제출 우회는 `terraform apply -var "producer_auth_mode=tls"` 로 명시. README·app/README·BINARY-ANALYSIS 를 "A. 정통(iam, 기본) / B. 대회 제출 우회(tls, -var)" 두 절로 분리하고 README 최상단에 경로 비교표를 넣었다. 배포 순서·검증 단계는 공통이고 `producer_auth_mode` 값 하나만 다르다
- 판별 자동화: 대회 당일 어느 모드인지는 **그날 지급된 제공 바이너리가 IAM 인증을 하느냐**로 갈리므로(출제 측이 바이너리를 교체하면 판정이 뒤집힌다), `select-auth-mode.ps1`/`.sh` 를 모듈 폴더에 두고 런북 **0단계**로 넣었다 — 제공 바이너리를 `check-binary-auth` 로 검사해 쓸 모드와 apply 명령을 그대로 출력한다. 대회장에서 "이번 배포본은 IAM 되나?"를 사람이 판단하지 않게 하는 게 목적이다
- 기각: (1) tls 를 기본값으로 전환 → 과제가 요구하는 올바른 구성이 기본에서 밀려난다. 대회 당일 한 번 `-var` 를 붙이는 비용이 더 싸다. (2) 자체 바이너리·iam 경로를 저장소에서 삭제(2026-08-17 중간에 한 번 커밋했다가 revert) → 대회 제출용으로 못 쓴다는 것과 정통 구성 연습·회귀 검증 자산으로서의 가치는 별개다
- 대가: 경로가 둘이라 "지금 어느 모드인지" 를 항상 의식해야 한다 — 최상단 비교표로 완화. 대회 당일 `-var` 를 빠뜨리면 제출 불가능한 구성으로 배포되므로 런북 B 절을 반드시 확인한다. tls 경로는 실배포 미검증이고, 과제지 "IAM 인증을 통해서만 접근" 문구를 그 경로에선 리터럴로 못 만족한다(제공 바이너리의 구조적 한계, BINARY-ANALYSIS.md). 채점 4-3 은 `Sasl.Iam.Enabled` 만 보므로 두 경로 다 통과. 마이스터넷 질의 마감(2026-08-13)이 지나 이 불일치는 게시판 정정을 받을 수 없다

### 2026-08-16 [module-4] producer 기본 인증 모드를 tls → iam 으로 뒤집는다
- 맥락: 과제지 개요가 "MSK 클러스터는 IAM 인증을 통해서만 접근 가능해야 합니다" 를 못 박는데,
  기본값 `producer_auth_mode=tls` 는 클러스터에 `unauthenticated=true` + 9094 리스너를 열었다.
  런북대로 배포하면 파이프라인은 도는데 요구는 위반한 상태로 채점에 들어간다.
  9094 TLS 는 전송 구간 암호화일 뿐 클라이언트 인증이 없다 — IAM(9098)과 층이 다르다.
- 채택: `variables.tf` 기본값과 `terraform.tfvars` 를 `iam` 으로 통일. `app/producer`(IAM 전용
  Go 바이너리, 저장소에 있음)로 9098 발행하고 클러스터는 `unauthenticated=false`.
  9094 SG 규칙(`security.tf`)도 `count` 로 tls 모드에서만 만들도록 좁혔다 — iam 모드에서는
  리스너가 없어 규칙만 남으면 불필요 오픈 포트가 된다.
- 근거: `check-binary-auth.sh` 로 두 바이너리 대조 — `app/producer` 는 IAM 마커 4/5 검출,
  제공 바이너리(`provided/module4/app`)는 0건. tls 모드는 **제공 바이너리를 살리기 위한
  호환 우회**이지 보안 설계가 아니다(`BINARY-ANALYSIS.md:10,88`).
- 기각: 기본 tls 유지 + 문서에 경고만 → 런북을 그대로 따르는 경로가 요구 위반이면 경고로는
  안 막힌다. 채점 스크립트(mark 4-3)가 `Sasl.Iam.Enabled` 만 보므로 tls 로도 4-3 은 통과하지만,
  과제지 문구가 채점 항목보다 넓다.
- 검증(2026-08-16 실배포): 클러스터 `Sasl.Iam.Enabled=True` / `Unauthenticated.Enabled=False`,
  `get-bootstrap-brokers` 에 TLS 문자열 자체가 없다. 그 상태로 `app/producer` 가 9098 로 발행해
  DynamoDB 적재와 alert 분기까지 정상 동작 — **IAM 전용으로 과제가 성립한다**
- 대가: 기본 경로가 자체 바이너리에 의존한다. 되돌릴 `tls` 경로는 코드에 남겨 두되 런북에서는
  뺐다(절차는 `BINARY-ANALYSIS.md` 호환성 참고 절). 모드 전환은 리스너 in-place 업데이트(~15-30분)다.

### 2026-08-16 [module-4] 첫 배포 확인을 고정 대기 → 폴링으로
- 맥락: 런북이 "3~5분 대기 후 DynamoDB 확인" 이었다. producer user_data 는 kafka 다운로드,
  IAM jar, 토픽 생성 재시도(최대 5분), S3 바이너리 수신, systemd 기동을 차례로 하고 그 위에
  ESM 활성화가 겹친다 — 3~5분에 데이터가 없어도 정상일 수 있어 오진을 유발한다.
- 채택: ESM 2개가 `Enabled` 될 때까지, 그리고 DynamoDB item 수가 1 이상이 될 때까지 폴링하는
  루프를 PowerShell·bash 양쪽 런북에 넣었다(각 최대 10분). 실패 시 진입점은 SSM
  `send-command` 로 `systemctl is-active app` + 부팅 로그를 뽑는 비대화형 경로.
- 실측 확인(2026-08-16): 두 루프 모두 **1회에 통과**했다. producer 는 apply 종료 1분 48초 전에
  이미 active 였고 첫 레코드·첫 alert 객체가 apply 종료 직후에 찍혔다 — "3~5분 대기" 는
  근거 없는 과대 대기였다. 루프는 실패를 빨리 드러내는 용도로 남긴다.
- 기각: 대기 시간만 늘리기(예: 10분 고정) → 빠르게 뜬 경우에도 그만큼 서게 된다.
- 함께: 정상 데이터만 보던 검증 절에 이상치 분기(S3 `alert/` 객체 + alert consumer 의
  `alert forwarded` 로그, 비면 sensor consumer 의 `ALERT -` 로그)를 PowerShell 런북에도 추가.
  기존엔 Linux 절에만 S3 한 줄이 있었다.
