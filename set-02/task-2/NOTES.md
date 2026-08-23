# set-02 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> RC 판(2026-08-23)에서 구 3번 Cloud Event Handling 이 삭제돼 **모듈 3개**다. 당일 최대 6개까지
> 늘 수 있다. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 리전 | 미해결 |
|------|------|------|--------|
| 1 | workflow | ap-southeast-1 | 없음. RC 로 채점 절차가 바뀌어 **채점 직전 버킷·테이블을 비운 상태**로 둔다 |
| 2 | analytics | ap-northeast-2 | 없음 |
| 3 | msk | ap-northeast-1 | iam(기본) 실배포 검증 2026-08-16. tls(`-var` 지정) 실배포 미검증. 당일 모드는 `select-auth-mode` 판정을 따른다. mark 3-3 의 `aws kafka list-topics` 는 실배포 미검증 |

> **번호 매핑**: 아래 결정 로그의 `[module-4]` 는 전부 지금의 **module-3-msk**, `[module-3]` 은
> 삭제된 event 모듈이다(git 이력 · 커밋 `6c9e827` 이전). 결정 로그는 append 전용이라 과거 태그를
> 고치지 않는다.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

### module-3(MSK, 당시 module-4) (2026-08-16 실 apply, `producer_auth_mode=iam`)

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
## 정정 로그
<!-- 과제지·채점지 정정과 그에 따른 구현 변경. 질의일·답변일·출처를 함께 적는다. 최신이 위로. -->

### 2026-08-23 [재배부] Release Candidate 판 배부 — 3번 Cloud Event Handling 과제 삭제
- 출처: 배부된 `day2 release candidate` 문제지(6p)·채점기준표(8p). PDF CreationDate 는 양쪽 다
  `2026-08-23`(macOS Quartz 재인쇄), 구판은 `2026-08-21` 신판이었다
- **이 저장소의 `task.pdf`·`mark.pdf` 를 RC 본으로 교체했다.** 구판 blob:
  `task 0f4c464b12b2f2101d9f5627ad4be4903f06014f`(108,698B),
  `mark b9de077ec2b85ee0facad04ce8f6bc3598a02048`(96,980B). 2026-08-21 재배부와 같은 방침이다
- 대조 방법: `pdftotext` 계열을 쓰지 않았다. PyMuPDF 로 **글자 색과 얇은 가로 그래픽 좌표**를
  span bbox 와 대조해 변경분을 뽑고, 그 위에 6+8 페이지를 **PNG 로 렌더해 육안 확인**했다
  (작업규칙 11). 변경분은 전부 파란색 `#0000ff`, 배점 2건만 빨간색 `#ff0000`, **취소선은 없다**
- 문제지 유의사항 12번과 채점지 유의사항이 "3번 Cloud Event Handling 삭제 / 4번 MSK 가 3번 채점
  항목" 을 명시한다. 총 배점 30 → **22.5** (7.5 × 3)

| # | 문서 | 변경 | 판정 |
|---|---|---|---|
| **T2/M1** | 양쪽 | 3번 Cloud Event Handling **삭제**, MSK 가 3번 | **구조 변경** — `module-3-event/`·`provided/module3/`·구 `mark2-3.sh` 삭제, `module-4-msk` → `module-3-msk`, `mark2-4.sh` → `mark2-3.sh` |
| T1 | 양쪽 | `비번호` → **`등번호`** | **수정완료** — 전사본·런북·변수 설명·mark 프롬프트 |
| **T5/T7/M4** | 문제지 m1 §1·§3, 채점지 1-0 | 선수는 **종료 전 버킷·테이블 데이터 전부 삭제**. 미삭제면 1-1·1-5·1-6 오답. 채점자가 `input/test.csv` 를 올리고 60초 뒤 확인 | **구현·런북 변경** — 아래 결정 로그 `[module-1]` 항목 |
| **T8** | 문제지 m1 §6 신설 | Workflow 플로우도 + "자동 실행은 트리거 Lambda", 입력 `{"key": "input/test.csv"}` | **구현 정합** — ASL 이 플로우도와 1:1이 됐다(같은 결정 로그) |
| T4 | 문제지 m1 개요 | 업로드부터 **60초 이내** 완료 | **영향없음** — 실측 수초. 런북 리허설에 `sleep 60` 만 넣었다 |
| T6 | 문제지 m1 §2 | Python **3.12** + `S3_BUCKET`·`DDB_TABLE` 환경변수 표 명문화 | **영향없음** — `variables.tf: lambda_runtime`·`lambda.tf` 가 이미 그 값 |
| T7b | 문제지 m1 §3 | "언급된 PK·SK 외 다른 KeyScheme 구성 금지" | **영향없음** — GSI/LSI 없음 |
| T9~T12 | 문제지 m2 | `Private Subnet **A**`, `/health` API 서빙, **TG Port 5000**, Kinesis 출력 샘플, **노트북 환경 버전 `ZEPPELIN-FLINK-3_0`** | **영향없음** — 전부 현행 구현값. 구판에서 "task.md 는 1.19 라는데 mark 는 ZEPPELIN…" 이라 달아둔 변수 주석만 걷어냈다 |
| T13 | 문제지 m3 §4 | `Instance Name` → **`Instance Tag : Name=...`** | **영향없음** — 이미 Name 태그 |
| **T14** | 문제지 m3 §6 | 속성 표가 module-1 복붙 오류에서 **정정**됨 → `humidity` **Number**, `temperature`·`location`·`status`·`sensorId`·`timestamp` String | **수정완료** — `sensor_consumer/index.py` 의 humidity 를 `Decimal` 로. temperature 는 채점 3-5 가 `.S` 로 조회하므로 String 유지 |
| T15 | 문제지 m3 §7 | AccessPointAlias 미설정 / head-bucket 이 `false` | **영향없음** — 일반 버킷이라 자동 충족 |
| M5 | 채점지 1-3 | 기대값 `…bucket-103` → **`<등번호>`** | **해소** — NAMING-AUDIT N3 이 이걸로 닫힌다 |
| M6 | 채점지 2-4 | `"price": "<number>"` → **`"price": <number>`** (quantity 동일) | **수정완료(전사본만)** — provided `app.py` 가 이미 숫자로 낸다 |
| **M7** | 채점지 3-3 | `aws kafka list-topics` **검사 추가** — 기대값 alert `2,1` / raw `2,3` | **수정완료(전사본·스크립트)** — 구현은 이미 그 파티션/RF. 아래 별도 항목 |
| M8 | 채점지 3-5·3-6 | "Value 는 달라도 **Key 는 모두 같아야**", 3-6 은 `+09:00` 표기 강제 | **영향없음** — 이미 충족 |
| M9 | 채점지 3-0 | `BUCKET_NAME="wsc2026-student-score-bucket-…"` 이 여전히 module-1 버킷명 | **미수정 원문 오류** — 기대 출력은 `wsc2026-sensor-alert-bucket-<등번호>` 이고 `mark2-3.sh` 도 후자를 쓴다. 질의 마감(2026-08-13) 경과로 게시판 정정 불가 |

- **`aws kafka list-topics` 는 실재하는 API 다.** MSK 컨트롤플레인의 `ListTopics`
  (`GET /v1/clusters/{clusterArn}/topics`, 응답 `Topics[].{TopicName,ReplicationFactor,PartitionCount}`)
  를 botocore 1.43 서비스 모델에서 확인했다. 토픽을 producer user_data 의 `kafka-topics.sh` 로
  만들어도 클러스터 메타데이터라 그대로 조회된다 — 토픽 생성 방식은 바꾸지 않았다.
  다만 **이 API 자체는 실배포로 확인하지 못했다**(모듈 현황 미해결 칸)
- 채점지 원문의 `—query`·`grep –A2`(em/en dash)는 조판 아티팩트로 보고 전사본에선 ASCII 로 적었다

### 2026-08-23 [기록] 원문 오류 3건 — 질의 마감(2026-08-13) 경과로 게시판 정정 불가, 구현 영향 없음
- task.md "4) MSK" §6 DynamoDB 속성 표가 module-1 내용(studentId/examDate/korean…) 복붙 오류.
  키 정의(PK sensorId / SK timestamp)와 mark 4-1 이 진짜 기준 — 구현은 키 스키마를 따른다
  (`module-4-msk/terraform/dynamodb.tf` 주석, README 함정 절에 기존 문서화)
- mark.md 4-0 채점 준비의 `BUCKET_NAME="wsc2026-student-score-bucket-…"` 은 module-1 버킷명
  오기. 실제 스크립트 `mark/mark2-4.sh` 는 `wsc2026-sensor-alert-bucket-<비번호>` 를 검사한다
- mark.md 채점기준표(3-4: SG/EC2 Type Remediation Test, 3-1 CloudTrail 0.5)와 세부 채점
  항목(3-1~3-5)이 불일치 — 세부 절차·스크립트에는 type 테스트와 CloudTrail 검증이 없다.
  채점기준표가 수행될 가능성에 대비해 type 레이스 가드를 넣었다(결정 로그 2026-08-23 module-3)

### 2026-08-21 [재배부] 문제지·채점기준표 신판 배부 — PDF 자체가 교체됐다
- 출처: 재배부된 `2과제_문제.pdf`·`2과제_채점기준.pdf` (PDF CreationDate `2026-08-21`, 구판은
  문제지 `2026-07-12` / 채점지 `2026-07-13`). 페이지 수는 양쪽 다 문제지 6p / 채점지 9p 로 동일
- **이 저장소의 `task.pdf`·`mark.pdf` 를 신판으로 교체했다.** 규칙 10 은 "출제자는 게시된 과제
  파일을 직접 고치지 않는다"를 전제로 원본 보존을 요구하지만 이번엔 그 전제가 깨졌다. 구판은
  git 이력에 LFS 오브젝트로 남는다 — 구판 oid: `task 48d127ec7cdeac16…`(108,322B),
  `mark 988773e9486cf09f…`(96,230B). 1과제도 같은 배부본이라 같은 방침으로 갔다
- 대조 방법: 구판을 `git lfs fetch` 로 받아 `pdftotext` 의 `-layout` 과 `-raw` 두 모드로 각각
  추출해 diff. 두 결과가 일치해 조판 리플로우에 가려진 변경이 없음을 확인했다
- 변경은 총 7건 (문제지 3 + 채점지 4)

| # | 문서 | 변경 | 판정 |
|---|---|---|---|
| T1 | 문제지 module-1 §2 | Lambda 함수 이름 `wsc2026-student-score-function` 을 명시 | **영향없음** — `module-1-workflow/terraform/variables.tf:28` 이 이미 이 이름. 구판 문제지엔 이름이 없고 `provided/module1/lambda.md` 로만 알 수 있었다 |
| T2 | 문제지 module-2 §2 | "애플리케이션은 systemd 서비스로 등록, 서비스 이름은 `app`" 추가 | **영향없음** — `module-2-analytics/terraform/userdata.sh.tpl:20` 이 이미 `app.service`. 채점 2-6 이 원래 이 이름을 봤고 문제지가 뒤늦게 명문화한 것 |
| **T3** | 문제지 module-2 §6 | `wsc2026-alaytics-ec2-role` → **`wsc2026-analytics-ec2-role`** (원문 오타 수정) | **수정완료** — 전사본(`task.md:157`) + 구현 리네임(`variables.tf`·`iam.tf`, 이슈 #133). 아래 별도 항목 |
| M1 | 채점지 세부표 | `3-2 SNS Topic` 0.5→1, `3-4/4-1 EventBridge Rules` 2→1.5, `4-2/2-1 Lambda Functions` 1→1.5, `4-3/3-1 MSK Cluster Configuration` 2→1.5 | **수정완료** — `mark.md` 세부표. 배점 이동이 module-3·4 **내부에서만** 일어나 모듈 합은 양쪽 다 7.5 로 불변 |
| M2 | 채점지 3-4 | `sleep 30` → `sleep 60` | **수정완료** — `mark.md` + `mark/mark2-3.sh`. SG 자동복구 람다가 도는 데 30초로는 모자란다고 본 것. 구현 변경은 없고 대기만 길어진다 |
| M3 | 채점지 4-1 | 예상 출력 `…bucket-586639730662` → `…bucket-<비번호>` | **수정완료(채점지 전사본만)** — 구판이 출제자 계정 ID 로 보이는 값을 고정 기재해 그대로면 오답 처리될 수 있었다. 1과제 2-1-A 와 같은 계열의 수정이다 |
| M4 | 채점지 4-5-B | `--output table` → `--output json`, 판정을 "JSON 형식 + `sensorId`·`timestamp` 만 포함 + ISO 8601 KST" 로 명문화 | **수정완료(채점지 전사본·스크립트만)** — 구현은 이미 충족. `provided/module4/Application.md:22` 가 timestamp 를 ISO 8601 KST 로 규정하고 `sensor_consumer/index.py:85` 가 producer 값을 문자열 그대로 저장한다 |

- **배점 재검산**: 주요항목 4개 모듈 × 7.5 = 30, 세부표도 모듈별 7.5 / 전체 30 으로 일치한다.
  이번 배점 변경은 총합이 아니라 **모듈 내 재분배**라서, 검증 포인트는 합계가 아니라 모듈별 합이었다

### 2026-08-21 [module-2] T3 리네임은 전사본만 반영하고 구현은 이슈로 넘겼다
- 경위: 저장소는 구판 원문 오타 `alaytics` 를 **의도적으로 유지**하고 `variables.tf:101`·`iam.tf:3`·
  두 README 에 "고치지 말 것" 주석까지 달아 뒀다. 신판이 원문을 고쳐 그 근거가 사라졌다
- 채택: 과제지 전사본(`task.md`)은 정본을 반영해야 하므로 `analytics` 로 고쳤다. `.tf` 리네임은
  이번 커밋에서 하지 않고 **이슈 #133** 으로 넘긴다 (사용자 결정)
- 당시 상태: **전사본 `analytics` ↔ 구현 `alaytics` 로 어긋나 있었다.** 두 README 의 "고치지 말 것"
  주의문은 이 사실과 이슈 번호를 가리키도록 재작성했고, `variables.tf`·`iam.tf` 의 같은 취지
  주석은 손대지 않아 이슈가 닫히기 전까지 무효로 읽어야 했다 (아래 종결 항목에서 해소)
- 위험 평가: 채점 스크립트(`mark/mark2-2.sh`, `mark.md` 2-1~2-6)는 이 역할 이름을 **조회하지 않는다**
  — 자동 채점 점수 영향 없음. 다만 문제지 §6 이 이름을 못 박는 항목이라 육안 확인 여지는 남는다
- 리네임 시 주의: 이름 변경이라 IAM Role 과 인스턴스 프로파일이 **재생성**된다(둘 다 `name` 이
  ForceNew). 다만 `aws_instance.iam_instance_profile` 은 ForceNew 가 아니라
  ReplaceIamInstanceProfileAssociation 으로 in-place 교체되므로 **EC2 는 재생성되지 않는다**.
  이미 apply 한 스택이 있으면 plan 을 먼저 확인할 것
- **종결(2026-08-21, 이슈 #133)**: 구현을 `wsc2026-analytics-ec2-role` 로 리네임하고
  `.tf` 의 "고치지 말 것" 주석과 두 README 주의문을 걷어냈다. 전사본 ↔ 구현 일치

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

### 2026-08-23 [공통] RC 판 반영 — module-3-event 삭제, MSK 를 module-3 으로 재번호
- 맥락: RC 문제지 유의사항 12번이 3번 과제를 삭제하고 채점지가 "4번 MSK 가 3번 채점항목" 을
  명시했다. 저장소가 구 번호를 유지하면 대회 당일 과제지 "3)" 과 디렉터리 `module-4-msk` 가
  어긋나 매핑을 사람이 매번 환산해야 한다 — 4시간짜리 경기에서 그 환산이 사고를 만든다
- 채택: `module-3-event/`·`provided/module3/`·구 `mark2-3.sh` 를 지우고 `module-4-msk` →
  `module-3-msk`, `mark2-4.sh` → `mark2-3.sh` 로 옮겼다. `.tf` 주석·런북·루트 문서의 채점 항목
  번호(`4-x` → `3-x`, `2-3-A/B` → `2-3/2-4` …)도 채점지 세부표와 1:1로 맞췄다. 삭제분은 git
  이력에 남으므로 3번 과제가 되살아나면 되돌릴 수 있다
- 부수: `provided/` 디렉터리 이름은 **module4 그대로** 뒀다 — 배부 zip 이 정하는 이름이고 아직
  재배부되지 않았다. 대신 `module-3-msk/terraform/variables.tf` 에 `provided_dir` 변수를 신설해
  당일 zip 이 재번호되면 tfvars 한 줄로 흡수한다(작업규칙 5)
- 기각: 디렉터리를 그대로 두고 문서로만 안내 — 이름이 곧 색인인데 색인이 틀린 채로 남는다.
  `_removed/` 로 옮겨 보관 — 배포 대상에서 빠졌다는 걸 눈으로 확인시켜 주는 대신, 당일 착오
  배포 위험이 남는다(git 이력으로 충분하다고 봤다)

### 2026-08-23 [module-1] 워크플로우의 input 삭제 단계를 없앤다 — 채점 클렌징 요구와의 충돌
- 맥락: RC 는 채점 시작 시 버킷이 **비어 있음을 먼저 확인**하고(아니면 1-1·1-5·1-6 전부 오답)
  채점자가 `input/test.csv` 를 올린다. 그런데 1-1 은 워크플로우가 끝난 뒤에도 `PRE input/` 을
  요구한다. 기존 구현은 `MoveToProcessed` → `DeleteInputProcessed` 로 input 객체를 지우고
  0바이트 `input/` 마커로 PRE 를 유지했는데, 그 마커가 클렌징 확인에서 잔존 데이터로 잡히면
  세 항목이 한꺼번에 날아간다. 마커를 지우면 이번엔 1-1 의 `PRE input/` 이 사라진다
- 채택: **삭제 단계를 없앤다.** `DeleteInputProcessed`·`DeleteInputError` 상태를 걷어내고
  `MoveToProcessed` 는 `End`, `MoveToError` 는 `WorkflowFailed` 로 바로 간다. 채점자가 올린
  `input/test.csv` 가 남아 `PRE input/` 이 뜨므로 마커(`aws_s3_object.input_marker`)를 지워
  버킷을 진짜로 비울 수 있다. sfn 역할의 `s3:DeleteObject` 도 함께 뺐다(최소권한)
- 부수 이득: 상태 구성이 RC 문제지 §6 플로우도(`[MoveToProcessed] → [End]`,
  `[MoveToError] → [Fail]`)와 **정확히 1:1**이 됐다. 육안 채점 여지도 같이 닫힌다
- 기각: (1) 마커 유지 + 런북에 "마커는 폴더 표시라 데이터가 아니다" 주석 — 판정 주체가
  채점자라 우리 주석으로 못 막는다. (2) 마커 유지 + 삭제 제거 이중 방어 — 버킷이 완전히 비지
  않아 클렌징 확인에서 지적받을 여지가 가장 크다
- 대가: `Move` 라는 상태 이름과 달리 원본이 input 에 남는다. 채점은 `processed/`·`error/` 목록만
  보므로 영향 없고, 런북 함정 절에 이유를 적었다

### 2026-08-23 [공통] bastion 을 module-2·4 에서 제거 — task-2 전체 "bastion 없음" 으로 통일
- 맥락: bastion 판정이 모듈별로 정반대였다(1·3 없음 / 2·4 있음). mark2-1~4.sh 는 전부
  CloudShell 실행 전제라 채점이 bastion 을 한 줄도 쓰지 않고, module-3 README 는 이미
  "Bastion 없음" 을 명시 결정한 상태였다. 유지 비용도 컸다 — AdministratorAccess 역할,
  SSH 22 0.0.0.0/0, 평문 패스워드 기본값(`ssh_password`)이 리뷰 규칙(과도 IAM·anyopen SG·
  평문 시크릿) 3개에 동시에 걸린다
- 채택: module-2·4 의 bastion.tf(역할·프로파일·EIP·인스턴스·SG)와 관련 변수(`ssh_password`·
  `bastion_instance_type`)·출력·런북 절차를 제거. module-4 의 kafka 디버깅은 producer EC2 에
  이미 있는 `/opt/kafka` CLI(SSM 경유)로 대체 — 단 producer 역할엔 `ReadData` 가 없어(최소권한)
  console-consumer 는 불가, 소비 확인은 DynamoDB 건수·consumer 로그로 한다. 부수: module-2 의
  미사용 `player_number` 변수 제거, module-3 tfvars 실습값(12345)을 플레이스홀더 103 으로 통일
- 반론(기록): 유의사항 7·10 은 "채점용 Bastion 생성, 모든 Resource Access" 를 문언으로 요구한다.
  채점 스크립트·채점 준비 어디에도 bastion 사용이 없어 사문으로 판단했지만, 육안 채점이 문언을
  본다면 감점 여지는 있다 — 그때는 git 이력의 bastion.tf 를 되살린다(모듈 독립이라 apply 추가로
  끝난다). 반대로 CLAUDE.md 는 "과제지가 요구하지 않는 bastion 은 불필요 리소스 감점"이라
  양쪽 리스크가 상쇄된다고 봤다

### 2026-08-23 [module-3] 채점 3-4 안정화 — type↔stop 레이스 가드 + SG 스위퍼 룰
- 맥락: ① 채점기준표에 "EC2 Type Remediation Test 1.5" 가 있는데(세부 절차는 없음) 채점자가
  실제 수행하면 type-remediation 의 stop→modify→start 도중 stop-remediation 이 먼저 start 를
  걸어 modify 가 `IncorrectInstanceState` 로 실패한다 — 기존 완화책(시연 전 룰 수동 비활성화)은
  채점 중 조작 불가라 무효. ② sg_change 는 CloudTrail 경유라 이벤트 전달이 수 분까지 늦을 수
  있는데 채점 3-4 는 authorize 후 sleep 60 한 번만 본다
- 채택: ① stop-remediation 에 타입 가드 — 현재 타입이 `INSTANCE_TYPE` 과 다르면 start 를 걸지
  않고 ALERT_ONLY 만 발행(원복은 type-remediation 몫). 수동 시연(사람이 stop→modify)은 stopping
  시점 타입이 아직 원값이라 가드를 통과하므로 여전히 룰을 먼저 끈다 — README 함정 절 갱신.
  ② `wsc2026-sg-sweep-schedule` rate(1분) 룰이 sg_remediation 을 스위퍼로 호출 — 기준선 인바운드
  0 이라 잔여 규칙 전부 revoke 가 곧 복구다. 이벤트 파싱 실패 폴백도 같은 sweep 으로 흡수하고,
  스위퍼 경유 호출은 실제 걷어낸 게 있을 때만 SNS 발행(1분 주기 스팸 방지)
- 검증: boto3 스텁 시뮬레이션 6케이스(정상 stop 복구 / 타입 변조 중 스킵 / 이벤트 revoke /
  스위퍼 잔여 제거 / 스위퍼 무동작·무알림 / 파싱 실패 폴백) 전부 통과. IAM 은 기존
  Describe*·Revoke(SG 스코프)로 충분해 추가 권한 없음
- 기각: type-remediation 이 `events:DisableRule` 로 stop 룰을 잠깐 끄는 안 — IAM 확장 + 끄고
  못 켜는 실패 모드(룰이 꺼진 채 남음)가 가드보다 나쁘다

### 2026-08-23 [module-4] check-binary-auth 판정을 "결정적 마커" 기준으로 강화 + ESM 권한 보강
- 맥락: 기존 판정은 마커 5개 중 하나라도 있으면 iam 이었다. 그런데 `kafka-cluster`·
  `AWS4-HMAC-SHA256`·`aws4_request` 는 MSK IAM 이 아니라 **SigV4 를 쓰는 모든 AWS SDK 바이너리**
  에 박히는 문자열이다 — 당일 교체 바이너리가 S3/SSM 만 호출해도 iam 오판 → 접속 불가 배포
- 채택: 판정을 결정적 마커(`AWS_MSK_IAM` 와이어 필수 문자열, `aws-msk-iam-sasl-signer` 모듈 경로)
  로만 하고 SigV4 3종은 보조(참고 출력)로 강등. sh/ps1 동일 로직, exit 계약(0=iam/1=tls/2=없음)
  불변. 검증: 실제 제공 바이너리(tls, 마커 0/5)·합성 IAM·SigV4-only 오탐 케이스·부재 4케이스 통과
- 함께: Lambda 역할에 `kafka-cluster:DescribeClusterDynamicConfiguration` 추가 — AWS Lambda MSK
  튜토리얼의 IAM 인증 ESM 필수 6액션 중 유일하게 빠져 있던 것(클러스터 ARN 스코프). 2026-08-16
  실배포는 이것 없이도 동작했으나 문서 요구 목록을 채워 회귀 위험을 없앤다. producer 의
  `WriteData` 는 raw 토픽으로 축소(alert 발행은 Lambda 몫 — "EC2 IAM 최소" 문언 대응),
  producer SG 의 9094 egress 는 MSK 쪽 인바운드와 대칭으로 tls 모드에서만 생성(count)

### 2026-08-23 [공통] 배포파일 저장소 제거의 후속 — 배부물 로컬 배치를 런북·.gitignore 로 명문화
- 맥락: 커밋 f395d62·2988555 가 배포 소스·바이너리·데이터(test.csv, app.py, requirements.txt,
  lambda-function.py×2, module4 app)를 당일 수정 대비로 저장소에서 뺐다. 그 뒤 module-2 는
  `ec2.tf` 의 `file()` 참조로 validate/plan 자체가 실패했고, module-4 는 tls 경로와 런북 0단계
  (`select-auth-mode`)가, module-1 은 test.csv 업로드 단계가 실행 불가였는데 런북 어디에도
  "배부물을 먼저 놓는다" 선행 단계가 없었다
- 채택: 배부물을 `provided/module<N>/` 원래 경로에 로컬 배치해 쓰는 운용을 task-2 README 와
  각 모듈 런북(1단계 또는 0단계 앞)에 명문화하고, 해당 6개 경로를 루트 `.gitignore` 에 추가해
  배치본이 커밋되지 않게 했다. `select-auth-mode.sh`·`teardown-eni.sh` 실행 비트도 이때 복구
- 실측(2026-08-23 배부 zip 기준): 텍스트 5개는 제거 전 git 이력과, module4 `app` 은 구 LFS
  포인터 sha256(e22e22b3…)과 완전 동일 — 즉 8/17 리버싱 분석(BINARY-ANALYSIS)이 그대로 유효.
  test.csv 를 처리 Lambda 로직에 통과시켜 mark 1-5-A/B 기대값 재현(processed 5건, STU1020
  96.6 A, error 정확히 STU2001·STU2002·STU2004·unknown 4건). `select-auth-mode` 실물 판정은
  tls(IAM 마커 0/5). 배치 후 module-2·module-4 `terraform validate` 통과
- 주의: 저장소 자체 바이너리 `module-4-msk/app/producer` 는 LFS 오브젝트라 LFS 미수신 클론에선
  133B 포인터다 — iam 경로로 apply 하면 포인터가 S3 에 올라간다. 런북 0단계에 확인 문구를 넣었다

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
