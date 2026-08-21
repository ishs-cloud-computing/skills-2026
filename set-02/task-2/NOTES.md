# set-02 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 기본 4개. 당일 최대 6개까지 늘 수 있다. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 리전 | 미해결 |
|------|------|------|--------|
| 1 | workflow | ap-southeast-1 | 없음 |
| 2 | analytics | ap-northeast-2 | EC2 Role 이름이 전사본(`analytics`) ↔ 구현(`alaytics`) 로 어긋남. 2026-08-21 신판이 원문 오타를 고쳤으나 `.tf` 리네임 미반영 — 이슈 #133 |
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
## 정정 로그
<!-- 과제지·채점지 정정과 그에 따른 구현 변경. 질의일·답변일·출처를 함께 적는다. 최신이 위로. -->

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
| **T3** | 문제지 module-2 §6 | `wsc2026-alaytics-ec2-role` → **`wsc2026-analytics-ec2-role`** (원문 오타 수정) | **전사본만 수정 / 구현 미반영** — 아래 별도 항목 |
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
- 현재 상태: **전사본 `analytics` ↔ 구현 `alaytics` 로 어긋나 있다.** 두 README 의 "고치지 말 것"
  주의문은 이 사실과 이슈 번호를 가리키도록 재작성했고, `variables.tf`·`iam.tf` 의 같은 취지
  주석은 손대지 않았으므로 **이슈가 닫히기 전까지 그 주석은 무효**로 읽어야 한다
- 위험 평가: 채점 스크립트(`mark/mark2-2.sh`, `mark.md` 2-1~2-6)는 이 역할 이름을 **조회하지 않는다**
  — 자동 채점 점수 영향 없음. 다만 문제지 §6 이 이름을 못 박는 항목이라 육안 확인 여지는 남는다
- 리네임 시 주의: 이름 변경이라 IAM Role 이 재생성되고 인스턴스 프로파일 교체가 따라온다.
  이미 apply 한 스택이 있으면 plan 을 먼저 확인할 것

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

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
