# set-02 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 기본 4개. 당일 최대 6개까지 늘 수 있다. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 리전 | 미해결 |
|------|------|------|--------|
| 1 | workflow | ap-southeast-1 | 없음 |
| 2 | analytics | ap-northeast-2 | 없음 |
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

### 2026-08-20 [module-2] Studio Notebook 카탈로그를 Glue → Flink 기본 인메모리로 전환
- 맥락: `flink.tf` 가 `aws_glue_catalog_database` 를 만들고 CFN 의 `ZeppelinApplicationConfiguration.CatalogConfiguration` 에 물려 노트북 카탈로그로 쓰고 있었다. 그런데 Glue 는 **과제 요구가 아니다** — `task.md`·`mark.md`·`mark/mark2-2.sh`·`provided/module2/*`·`errata/*` 전부에서 `glue` 등장 0회. 과제지 5 는 Studio Notebook 구성 + read-only `SELECT` 2개 실행만 요구하고 싱크·저장 요구가 없다. 채점 2-4 의 projection 은 `[ApplicationName, ApplicationStatus, RuntimeEnvironment]` 라 `ApplicationConfiguration` 을 아예 안 읽는다. Glue 에 들어가던 것도 데이터가 아니라 `CREATE TABLE`/`CREATE VIEW` 의 DDL 스키마뿐이었다 (주문 데이터는 Kinesis, 쿼리 결과는 이미 Flink 인메모리 + Zeppelin 화면 출력)
- 채택: CFN 템플릿에서 `CatalogConfiguration` 블록을 빼 노트북이 Flink 기본 인메모리 카탈로그(`GenericInMemoryCatalog`)를 쓰게 했다. 딸려서 `aws_glue_catalog_database`, `data.aws_iam_policy_document.flink` 의 `GlueCatalog` statement, `time_sleep.flink_policy_propagation`, `glue_db_name` 변수·output, `time` provider, `data.aws_caller_identity`(Glue ARN 조립 전용이었음)를 제거. CFN 스택의 `depends_on` 은 `aws_iam_role_policy.flink` 로 옮겼다. **`CustomArtifactsConfiguration` 의 `flink-sql-connector-kinesis:1.15.4` 는 유지** — 빼면 `Could not find any factory for identifier 'kinesis'`
- 근거: 제거로 **이 저장소가 실측한 실패 모드 3개가 함께 사라진다.** (1) KinesisAnalyticsV2 가 스택 생성 시 role 로 `glue:GetDatabase` 를 동기 호출해 검증하는데 IAM 전파 전이면 CFN ROLLBACK — 30초 `time_sleep` 은 보장이 아니라 타이밍 땜질이었다. (2) Glue IAM 을 analytics DB 로만 스코프했더니 Zeppelin 이 SQL 플래닝 때 `hive`/`default` 를 탐침해 `database/hive` 에서 AccessDenied — 카탈로그 전체 와일드카드로 넓혀 우회한 상태였고, 이게 과제지 6 "IAM Role에는 최소권한이 적용되어야 합니다" 와 정면 충돌했다. 지금은 Flink 역할이 Kinesis 읽기 전용이다. (3) Glue 영속성 때문에 재시연 시 stale DDL 이 충돌해 `DROP TABLE order_stream;` 선행이 필요했다 — 인메모리엔 그 함정이 없다
- 기각: (1) **현행 유지** — 처음엔 "검증된 구성" 이라는 이유로 유지를 권고했으나, 유지 근거로 들었던 두 가지가 실제로는 약했다. "인터프리터 재시작마다 DDL 재입력" 은 과장 — Zeppelin **문단 텍스트는 노트에 저장**되므로 ▶ 한 번 더 누르면 끝이고, Glue 가 아끼는 건 클릭 한 번이다. "30% 변동으로 S3 싱크가 추가될 때 카탈로그 필요" 도 약하다 — `CREATE TABLE ... WITH ('connector'='filesystem')` 은 인메모리 카탈로그에서도 되고 Glue 는 정의의 **영속화**에만 관여한다. (2) **Glue 유지 + IAM 리소스만 축소**(`database/hive`·`database/default` 명시 열거) — 탐침 대상 DB 목록이 런타임·플래너 버전에 매달려 있어 또 다른 미검증 가정이 된다. 카탈로그 자체를 안 쓰면 탐침도 없다
- 대가: **`CatalogConfiguration` 생략 경로가 미검증이다.** AWS 자료가 엇갈린다 — API 레퍼런스는 `CatalogConfiguration` 을 `Required: No` 로 명시하지만, 제품 문서·콘솔은 Studio 의 SQL 카탈로그 = Glue 카탈로그를 기본 전제로 서술하고("Studio notebooks store and get information about their data sources and sinks from AWS Glue"), 생략 경로가 동작한다는 문서·사례는 찾지 못했다. 실측 관문 둘 — **(1) CFN 스택이 `CREATE_COMPLETE` 되는가, (2) 문단 2 의 `CREATE TABLE` 이 통과하는가.** 둘 다 배포 시점에 시끄럽게 실패하므로 채점 당일 조용히 틀리는 종류는 아니다. 실패하면 `aws_glue_catalog_database` + Glue IAM statement + `CatalogConfiguration` + `time_sleep` 을 함께 복원(이 커밋 revert)하고 실패 지점을 여기 append 한다. 그 외 상시 대가는 노트북 중지 시 DDL 소실 — README 6단계에 반영했다
- 미확인: 이 변경은 `terraform fmt` 까지만 통과했다. `validate`·`plan`·`apply` 는 미실행 (작업 환경에 registry 접근이 막혀 provider 설치 불가). 본 PC 에서 관문 1·2 를 반드시 확인할 것

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
