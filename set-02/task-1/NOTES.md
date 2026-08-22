# set-02 / task-1

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.

## 현재 상태

- 구성: Terraform(VPC·SG·KMS·S3·ECR·DynamoDB·Lambda·ALB·CloudFront·IAM) + eksctl(EKS 1.35,
  addon/app NG, IRSA) + k8s(book 앱, kube-prometheus-stack, Fluent Bit). 런북은
  README.md(PS7, 주) / README.linux.md(bash, 부). 플레이스홀더는 전부 `${ENV_VAR}`
  (envsubst 스타일)로 통일 — k8s 는 `rendered/` 로 렌더 후 `kubectl apply -R -f rendered/` 일괄 적용.
- 미해결:
  - 9-2-A 예상 출력이 `created_at`·`booking_id` 까지 포함한 고정 문자열에 "정확히 일치" 판정이다
    (`mark.md:425-431`). 요청마다 앱이 새로 만드는 값이라 어떤 구현으로도 재현할 수 없다.
    **이 세트에는 이 항목에 대한 정정 답변이 없다** — `booking_id` 는 예시값이라는 답변도,
    `created_at` 을 `date` 기준 1분 이내로 본다는 답변도 전부 set-03 정정본의 내용이다
    (2026-08-16 [출처 정정] 항목). 대회 당일 심사장 확인 사항.
  - ~~Monitoring 배점 대분류 3.5 ↔ 세부 합 5 불일치~~ → **2026-08-21 신판에서 해소.**
    출제자가 Monitoring 을 4 로, ECR 을 1 로 조정해 대분류·세부표가 10개 항목 모두 일치하고
    세부 합도 정확히 30 이 됐다(구판 31.5). 아래 2026-08-21 항목 참조.
  - 실배포 검증은 대회 계정에서만 가능한 항목 잔존 (grafana TGB 선적용 재시도 확인 등).

## 채점 커버리지

- mark.sh 전 항목 구현 완료 상태로 인계받음 (README 요구사항 ↔ 구현 매핑 표 참조).
  2026-07-27 변경은 런북 절차(렌더 검증·일괄 apply)만 바꾸며 리소스 구성엔 손대지 않았다.
- 2026-08-16 정정 반영 후 상태 (근거는 아래 정정 로그):

| 항목 | 정정 내용 | 판정 | 근거 |
|------|-----------|------|------|
| 1-1-A | subnet-d prefix `/242`→`/24` | 영향없음 | `terraform/variables.tf:37` 이미 `172.16.2.0/24`, `mark.md:114`도 `/24` |
| 2-1-A | 버킷명 `<비번호>` 채점 제외 | 수정완료 | 구현은 `terraform/data.tf:5`(`var.player_number`)로 이미 변수화. 채점지 전사본 `mark.md`의 리터럴 `-103` 제거 |
| 4-1-A / 9-2-A | DynamoDB GSI 과제지 명시 | 수정완료 | 구현은 `terraform/dynamodb.tf:28-41`에 이미 존재. 과제지 전사본 `task.md` §7 에 GSI 줄 추가 |
| 7-2-A | ALB 예상출력 `wskorea26-cf`×2 + `403` | 영향없음 | `terraform/alb.tf:84-120` 헤더 조건 규칙 2개 + listener default 403(`:72-79`), `mark.md`도 이미 최신본 |
| 10-0 | Grafana 접속 게이트 신설 | 수정완료 | 채점지 `mark.md`·`mark.sh` 10절 교체. 접속 경로·계정은 `README.md:262-263`, `terraform/outputs.tf:76-78`과 이미 일치 |
| 10-1-A | book app CPU/Memory | 수정완료 | `dashboard.json:36,51` `namespace=~"$namespace"` + 변수 기본값 `wskorea26` — 열면 book app 파드만 보인다 |
| 10-2-A | 실행중인 **book app** Pod 개수 | 수정완료 | `dashboard.json:68` 이 클러스터 전역 합계라 book app 개수를 읽을 수 없었다. `namespace="wskorea26"` 고정으로 한정 |
| 10-3-A | book app 재시작 횟수 | 수정완료 | `dashboard.json:83` 위와 동일 |
| 10-4-A | book app 네트워크 수신량 | 수정완료 | `dashboard.json:98` 위와 동일 |
| — | HighLatency Alert 채점 항목 삭제 / 로그 `level` 필드 / DataSource 이름 / `booking_id` 예시값 | **대상 아님(set-03)** | 근거 파일 `수정사항.txt` 가 set-03 정정본이었다. 이 세트엔 Alert·로그 형식·DataSource 채점 항목 자체가 없다 → `set-03/errata/수정사항(1).txt` 로 이관, 판정은 `set-03/task-1/NOTES.md` |
| — | `static/ PASS` 객체 채점 제외 (`6-1`) | **대상 아님(set-03)** | 이 세트 2-2-A(`mark.md:159`)는 `web/main/` 2개 객체만 보고 `--prefix "static/"` 명령 자체가 없다. set-03 6-1 항목이다 |
| — | `created_at` 을 `date` 기준 1분 이내 검증 (`9-3`) | **대상 아님(set-03)** | 이 세트 9-3-A 는 400 코드 확인이다. set-03 9-3 항목이라 이 세트 9-2-A 의 "정확히 일치" 문구는 그대로 남는다 (위 미해결) |
| — | 부하 Pod 생성 단계 이동 (`11-1`/`11-3`) | **대상 아님(set-03)** | 이 세트엔 부하/crash 파드 manifest 도 11절도 없다. set-03 11-1/11-3 항목이다 |

- **2026-08-21 신판 배부 후**: 위 표의 `2-1-A`·`4-1-A / 9-2-A`(GSI)·`10-0`·`10-1~4` 는 신판 본문에
  정식 반영돼 더 이상 "정정으로 선반영한 것"이 아니다. 신판이 추가로 바꾼 건 배점(ECR·Monitoring)과
  문제지 §11 헤더 값 두 축뿐이고 **구현 변경은 없다**. 상세는 아래 2026-08-21 정정 로그.

## 실측 소요시간

- terraform apply: (미실측)
- EKS 노드 준비: eksctl create cluster 약 20분 (README 기준)
- 기타 병목: CloudFront Deployed 전파 수 분

---
## 이름 감사 (2026-08-22, 미해결)
<!-- 과제지·채점지 원문의 이름 오탈자/불일치와 그 판정. 해소되면 정정 로그로 옮기고 여기서 지운다. -->

원문의 이름을 전부 추출해 `task.md` ↔ `mark.md` ↔ `mark.sh` ↔ 구현으로 교차 대조했다.
**구현이 채점 스크립트 이름을 못 맞추는 건은 없다.** 남은 건 원문 자체의 표기 문제다.

| # | 위치 | 내용 | 판정 |
|---|---|---|---|
| N1 | `task.md:135-138` Reference01 | IGW/NAT 만 `book-igw`·`book-ngw-c`·`book-ngw-d` 로 접두사가 `wskorea26-` 에서 벗어난다. 같은 표의 VPC·서브넷·RTB 는 전부 `wskorea26-` | **원문대로 유지.** 채점 1-2-A 는 이름이 아니라 `igw-…`/`nat-…` **ID** 만 읽는다. `variables.tf:46,52` 가 원문 그대로 |
| N2 | `task.md:167` ↔ `:169` | Lambda 경로가 표는 `/reserv-query`, 예시는 `/reserv_query` | **영향없음.** `alb.tf:84-118` 이 경로가 아니라 HTTP method 로 분기해 어느 쪽이 와도 통과 |
| N3 | `task.md` Reference02/03 | `concert_name` 예시값이 `2ND_TINY_CON`(Request) ↔ `2ND TINY_CON`(Response) ↔ `2ND%20TINY_CON`(쿼리)로 세 군데가 다르다 | **미해결.** 9-x E2E 는 채점자가 입력한 값을 그대로 되돌려주면 되므로 구현 영향은 없다. 당일 채점자가 어느 표기로 POST 하든 그 값이 GET 응답에 그대로 나와야 한다 |
| N4 | `task.md:113` | "Distribution **Name**" 이라 적었지만 CloudFront 에 Name 속성이 없다. 채점은 **Comment** 로 조회(`mark.sh:9`) | **양쪽 방어.** `cloudfront.tf:41` comment + `:114` Name 태그를 같이 세팅 |
| N5 | `task.md` 전체 | ServiceAccount 이름을 과제지·채점지 어디에도 명시하지 않는다 | **자체 명명.** `wskorea26-book-sa`. 채점 대상 아님 |

### 하드코딩 — 이름 정정이 오면 즉시 못 바꾸는 지점

작업 규칙 5(바뀌기 쉬운 축은 변수화) 미적용 구간. 30% 변동이나 당일 정정으로 이름이 바뀌면
`.tf` 를 직접 열어 고쳐야 한다.

| 파일:줄 | 리터럴 |
|---|---|
| `terraform/alb.tf:26,46,134` | `wskorea26-book-tg` · `wskorea26-lambda-tg` · `wskorea26-grafana-tg` |
| `terraform/iam.tf:28,36,54` | `wskorea26-book-app-policy` · `wskorea26-lbc-policy` · `wskorea26-fluent-bit-policy` |
| `terraform/security.tf:17,38,61,107` | `wskorea26-book-alb-sg` · `wskorea26-grafana-alb-sg` · `wskorea26-node-sg` · `wskorea26-cluster-extra-sg` |
| `terraform/cloudfront.tf:12,20` | `wskorea26-book-rewrite` · `wskorea26-s3-oac` |
| `terraform/dynamodb.tf:29` | GSI `concert_name-created_at-index` (과제지 명시값이라 위험도 낮음) |

TG 3종은 채점 7-x 가 이름을 직접 읽지는 않지만 ALB 규칙과 TargetGroupBinding 이 물려 있어
바꿀 때 `k8s/app/targetgroupbinding.yaml`·`k8s/monitoring/grafana-targetgroupbinding.yaml` 을
같이 고쳐야 한다. 나머지는 채점 비대상이라 우선순위가 낮다.

## 정정 로그
<!-- 과제지·채점지 정정과 그에 따른 구현 변경. 질의일·답변일·출처를 함께 적는다. 최신이 위로. -->

### 2026-08-21 [재배부] 문제지·채점기준표 신판 배부 — PDF 자체가 교체됐다
- 출처: 재배부된 `1과제_문제.pdf`·`1과제_채점기준.pdf` (PDF CreationDate/ModDate `2026-08-21`,
  구판은 `2026-07-02`). 페이지 수는 양쪽 다 문제지 7p / 채점지 10p 로 동일
- **이 저장소의 `task.pdf`·`mark.pdf` 를 신판으로 교체했다.** 규칙 10 은 "출제자는 게시된 과제
  파일을 직접 고치지 않는다"를 전제로 원본 보존을 요구하지만, 이번엔 그 전제가 깨졌다. 구판은
  git 이력에 LFS 오브젝트로 남는다 — 구판 oid: `task ca251902db55a8a5…`(126,972B),
  `mark 03121625031bd51b…`(103,440B)
- 대조 방법: 구판을 `git lfs fetch` 로 받아 `pdftotext -layout` 과 `-raw` 두 모드로 각각 추출해
  diff. 두 결과가 완전히 일치해 리플로우에 가려진 변경이 없음을 확인했다
- **2026-08-22 재검증: 위 대조 방법은 불충분했다.** 텍스트 추출은 글자색과 취소선을 버린다.
  신판의 수정은 빨간색(`#ff0000`)으로, 삭제는 취소선으로 표시돼 있어 두 축이 통째로 안 보였다.
  `pymupdf` 로 span 색상과 얇은 가로 그래픽(취소선) 좌표를 텍스트 bbox 와 대조해 다시 읽었고,
  그 결과 아래 두 항목을 정정한다
- 변경은 총 7건. **구현(`*.tf`·`k8s/*.yaml`) 변경은 0건**이다

| # | 문서 | 변경 | 판정 |
|---|---|---|---|
| T1 | 문제지 §7 | GSI `concert_name-created_at-index` 줄 추가 | **이미 반영** — 2026-08-07 답변으로 선반영했던 `task.md` 줄이 정식화됐다. 구현도 `terraform/dynamodb.tf:28-41` 로 이미 존재 |
| T2 | 문제지 §11 | `wskorea26-s3-access` → `wskorea26-s3-access: true` | **수정완료(전사본만)** — 헤더 값이 문제지에 명시됐다. 구현은 `terraform/variables.tf:141` 이 이미 `value = "true"` 라 변경 없음. 채점지 8-4-A 예상 출력도 구판부터 `true` 였다 |
| M1 | 채점지 주요항목표 | ECR `1.5→1`, Monitoring `3.5→4` | **수정완료** — `mark.md` 2-1 표 |
| M2 | 채점지 세부표 | `3-1` `1.5→1`, `10-1` `1.5→1`, `10-2` `1.5→1` | **수정완료** — `mark.md` 2-2 표 + 각 항목 헤딩 배점 |
| M3 | 채점지 2-1-A | 예상 출력 `…bucket-103` → `…bucket-<선수비번호>` | **이미 반영** — 2026-08-07 답변으로 리터럴 `103` 을 이미 뺐다. 신판 표기에 맞춰 토큰만 `<선수비번호>` 로 정렬 |
| M4 | 채점지 10절 | 10-0 사전 준비 신설, 10-1~4 를 `book app` 기준으로 재정의 | **이미 반영** — 2026-08-07 답변(`errata/질의 답변(1).txt`)과 문면이 일치한다. 정정 주석만 "신판 정식 반영"으로 갱신 |
| — | 문제지 §9/§12 | Function Name·Grafana 메트릭 문장의 페이지 경계 이동 | **영향없음** — 내용 동일, 조판 리플로우 |

- **배점 재검산**: 신판 세부 합 = 1+2+1+1+5+1+2.5+6.5+6+4 = **30**, 대분류 10개 항목이 전부 일치한다.
  구판은 세부 합 31.5 로 어긋나 있었고(2026-08-16 항목) 이를 ECR −0.5, 10-1 −0.5, 10-2 −0.5 로
  맞췄다. **위 「미해결」의 배점 불일치 건은 이것으로 종결**
- **9-2-A 는 신판에서도 그대로다.** 예상 출력이 `created_at`·`booking_id` 포함 고정 문자열에
  "정확히 일치" 판정인 문제는 손대지 않았다 → 「미해결」 유지, 대회 당일 심사장 확인 사항
- **정정(2026-08-22): `10-1-A (명령어 입력)` 칸은 남은 게 아니라 삭제됐다.** PDF p10 에서 `10-1-A`·
  `(명령어 입력)`·`브라우저를 사용해 출력되는 경로로 접속합니다.`·ALB DNS 조회 명령 3줄까지
  전부 취소선이 그어져 있다. 신설된 10-0 이 이를 대체한다. 결론(채점 대상 아님)은 2026-08-07
  답변과 같지만 근거가 "중복이라는 우리 판단"이 아니라 "출제자가 삭제"로 바뀐다
- **정정(2026-08-22): `/242` 오타는 신판에서 고쳐졌다.** PDF p4 는 `172.16.2.0/24`(검정) 뒤에
  빨간 `2` 를 두고 **그 한 글자에만 취소선**을 그었다 — 취소선 `x 384.5~391.0`, 글자 bbox
  `x 384.5~390.8`, 선 `y 684.5` 가 글자 세로 중앙이다. 텍스트만 뽑으면 `/24`+`2` 로 이어져
  `/242` 로 읽히는 게 위 오판의 원인이다. 구현·전사본은 이미 `/24` 라 조치 없음
- p2 주요항목표에서 빨간 `1` 이 ECR 행이 아니라 **NoSQL 행**에 찍혀 있다(ECR 배점 `1` 은 검정).
  두 항목 다 신판 값이 `1` 이라 합계 30 에는 영향이 없다. 출제자의 셀 착색 실수로 본다

### 2026-08-16 [출처 정정] `errata/수정사항.txt` 는 set-03 정정본이었다 — 삭제하고 이관
- 경위: 이 파일의 4개 문답(HighLatency Alert 삭제, Reference02 로그 `level`, 11-2 DataSource 이름,
  `booking_id` 예시값)은 전부 **11절·Alert 채점 항목이 있는 세트**의 것이다. 이 세트 채점지는
  대분류 1~10 이고 Alert·로그 형식·DataSource 항목이 아예 없다. set-03 `mark.md` 의
  11-1~11-4·6-1·9-3 과 정확히 대응한다
- 조치: `set-02/errata/수정사항.txt` 삭제, `set-03/errata/수정사항(1).txt` 로 이관.
  이 파일을 근거로 삼았던 판정 2건(HighLatency 삭제 / `booking_id` 예시값)을 이 로그에서 지우고
  커버리지 표를 **대상 아님(set-03)** 으로 바꿨다. set-02 파일 변경은 애초에 없었다
  (두 판정 모두 "영향없음"이었다) — 되돌릴 구현 변경 없음
- 파급: 9-2-A 의 "정확히 일치" 를 완화해 줄 답변이 이 세트엔 **없다**. 위 미해결 참조
- 이 세트의 정정 정본은 `errata/질의 답변.txt`·`errata/질의 답변(1).txt` 둘뿐이다

### 2026-08-16 [10] Monitoring 배점 3.5 ↔ 5 불일치는 원본 mark.pdf 자체의 오류
- 출처: `mark.pdf` 원문. 표 레이아웃 때문에 기본 추출이 열 단위로 깨지므로
  `pdftotext -f 3 -l 3 -table mark.pdf -` (xpdf table 모드)로 행 정렬해 확인
- 확인 결과: 주요항목표(p.2)는 `Monitoring 3.5` + 합계 `30`, 세부표(p.3)는
  `10-1 Grafana Dashboard Check 1.5 / 10-2 POD 1.5 / 10-3 RESTART 1 / 10-4 NETWORK 1` 합 5.
  세부표 전체 합은 31.5 다. 나머지 9개 대분류는 양쪽이 정확히 일치(예: CloudFront 6.5 =
  1+1.5+1.5+1+1.5, Application 6 = 1.5×4)하므로 어긋나는 건 10절뿐이다
- 판정: **영향없음(전사 오류 아님)** — `mark.md:39`(3.5)·`mark.md:68-71`(합 5) 둘 다 원본을
  그대로 옮긴 값이라 고칠 대상이 없다. 어느 쪽이 정본인지는 원본만으로 판별 불가 →
  대회 당일 배부본 확인 사항으로 남긴다. 배점이 어느 쪽이든 10-1~4 패널은 전부 구현돼
  있어 구현 변경은 없다
- 2026-08-07 정정으로 신설된 10-0 접속 게이트에는 배점 배정이 없다(`errata/질의 답변(1).txt:3-9`)

### 2026-08-16 [취합본] set-02 와 set-03 이 섞인 취합본이다 — 이 세트 몫만 반영
- 출처: `errata/질의답변-취합-20260816.txt` (심사장 공유 자료 기반 선수 취합본)
- 내용: 취합본은 Grafana 를 `11-1`·`11-3`, S3 KMS 를 `6-1`, 로그·Alert 항목을 별도 번호로 부른다.
  이 세트 채점지는 대분류 1~10 이고 Monitoring 이 10, 6-1-A 는 Lambda, S3 KMS 는 2-2-A 다
  (`mark.pdf` 원문 대조 — 배점열 `1,2,1.5,1,5,1,2.5,6.5,6,3.5` 합 30 이 `mark.md:39` 표와 일치)
- 판정: `1-1-A`·`2-1-A`·`7-2`·`[7] GSI`·`[10-1~4 (12)]` 가 이 세트 몫이고 전부 반영했다.
  나머지(`11-x`, `6-1` S3 KMS, `9-3` created_at, `5-4`, App Logs, DataSource)는 **set-03 몫**이다 —
  set-03 채점지에 `11-1 Observability Deploy`·`11-2 Grafana Datasource`·`11-3 Grafana Dashboard`·
  `11-4 Alert Firing`·`6-1 S3 Bucket`·`9-3 POST & GET E2E` 가 그대로 있고 문항 내용까지 일치한다
  (`set-03/task-1/mark.md`). 반영은 `set-03/task-1/NOTES.md` 정정 로그에 있다
- **"다른 판본 채점지" 가설은 폐기**한다. 두 세트가 한 문서에 섞였을 뿐이고, 이 세트 채점지가
  11 절까지 갈 근거는 없다. 배부본 번호 체계 확인은 여전히 하되 재판정 대상은 없다
- 충돌 처리: 10-1~4 스코프가 정본은 "book app 파드", 취합본은 "모든 파드(All Pod)"로 어긋난다.
  정본 우선 원칙에 따라 book app 기준으로 가되, CPU/Memory/재시작/네트워크 4패널은
  `sum by (namespace, pod)` 를 유지해 양쪽 다 통과시킨다 (아래 결정 참조)

### 2026-08-07 [10-1~4] Grafana 메트릭 범위 구체화 — Pod 개수 패널만 book app 한정
- 질의일: (게시판 접수) / 답변일: 2026-08-07. 출처: `errata/질의 답변(1).txt:1-12`
- 내용: 과제지 12 의 메트릭 조회 대상이 모호하다는 질의에 10-0 접속 게이트 신설 +
  10-1~4 를 `book app` 파드 기준 5지표로 재정의하는 답변. `10-1-A` 의 「명령어 입력」 항목은 제외
- 채택: `dashboard.json` 의 Pod 개수 패널만 `namespace="wskorea26", pod=~"wskorea26-book-deploy-.*"`
  로 한정. 나머지 4패널은 전역 `sum by (namespace, pod)` 유지 — 범례에 book app 파드가 그대로
  나오므로 정본("book app 지표를 확인할 수 있을 경우 정답")과 취합본(All Pod) 양쪽을 동시에 만족한다
- 기각: 5패널 전부 book app 필터 → 정본에는 정확히 맞지만 취합본의 All Pod 요구를 깨뜨린다.
  `kube_pod_labels` 조인으로 `label_app` 매칭 → kube-state-metrics 의 라벨 sanitize 규칙에
  의존이 하나 더 붙는다. ~~Pod 이름 prefix 는 Deployment→ReplicaSet→Pod 명명을 k8s 가 보장하고
  `wskorea26-book-deploy` 는 과제지가 못 박은 이름이라 더 안전하다~~ → **근거 오류. 2026-08-22 항목에서 정정**
- 대가: Pod 개수 패널이 book app 전용이 되어 클러스터 전체 파드 수는 이 대시보드에서 안 보인다

### 2026-08-07 [2-1-A] S3 버킷명 비번호 채점 제외
- 답변일: 2026-08-07. 출처: `errata/질의 답변.txt:4-5`, `errata/질의 답변(1).txt:21-22`
- 판정: **수정완료(채점지 전사본만)** — 원본 채점지가 `<비번호>` 자리에 `103` 을 고정 기재해
  비번호가 103 이 아니면 오답 처리될 수 있었다. `mark.md` 의 리터럴을 `<비번호>` 로 되돌렸다.
  구현은 `terraform/data.tf:5` 가 `var.player_number` 를 붙이는 구조라 변경 없음

### 2026-08-07 [1-1-A] subnet-d prefix `/242` 오타
- 답변일: 2026-08-07. 출처: `errata/질의 답변.txt:1-2`
- 판정: **영향없음** — `terraform/variables.tf:37` 이 이미 `172.16.2.0/24`, `mark.md:114` 전사본도
  `/24` 다. 구판 `mark.pdf` 에만 남아 있던 오타이고, 2026-08-21 신판이 취소선으로 정정했다
  (2026-08-21 항목의 2026-08-22 정정 참조)

### 2026-08-07 [7 / 4-1-A] DynamoDB GSI 요구사항 과제지 명시
- 답변일: 2026-08-07. 출처: `errata/질의 답변(1).txt:26-43`
- 판정: **수정완료(과제지 전사본만)** — Reference03 이 `concert_name` 조회·`created_at` 최신순
  정렬을 요구하는데 원본 과제지엔 PK `client_id` 만 있었다. `task.md` §7 에 GSI 줄을 추가.
  구현은 `terraform/dynamodb.tf:28-41` + `terraform/lambda/index.py:51-55`(`ScanIndexForward=False`)
  로 이미 반영돼 있었다

### 2026-08-07 [7-2-A] ALB 예상 출력은 최신 채점지 기준
- 답변일: 2026-08-07. 출처: `errata/질의 답변.txt:7-14`
- 판정: **영향없음** — 최신 기준 `wskorea26-cf` 2회 + `403` 이고, `mark.md:316-322` 전사본이 이미
  그 형태다. 구현도 헤더 조건 규칙 2개(`terraform/alb.tf:84-120`) + default 403(`:72-79`)

---
## 결정 로그

### 2026-08-22 step 2 이미지 빌드 입력을 CloudShell 업로드 UI → S3 릴레이(book) + 붙여넣기(Dockerfile)
- 맥락: set-07 task-1 이 쓰는 방식으로 통일했다. 기존 런북은 `book` 과 `Dockerfile` 을
  **Actions → Upload file** 로 올리게 했는데, ① 업로드는 손으로 파일 두 개를 고르는 수동 단계라
  재시도(세션 만료·리빌드)마다 반복되고, ② VPC environment 는 업로드 자체가 막혀 있어 셸을
  잘못 열면 그 자리에서 막힌다
- 채택: 붙여넣을 수 없는 것(8.4MB `book` 바이너리)만 step 1 에서 `s3://<web bucket>/_transfer/book`
  으로 올리고 CloudShell 이 `aws s3 cp` 로 받는다. 텍스트인 `Dockerfile` 은
  `cat > Dockerfile <<'DOCKEREOF'` 로 붙여넣고 `wc -l`(23) 로 줄 수를 대조한다
- `sed -i 's/\r$//' Dockerfile`: Windows 클립보드가 붙이는 CRLF 가드. `COPY --chmod=755 book /book`
  뒤에 `\r` 이 남으면 조용히 어긋난다. Linux 런북에는 불필요하므로 넣지 않았다
- 릴레이 객체는 step 2 끝에서 `aws s3 rm` 한다. 이 버킷은 채점 대상이라(mark 2-1) `_transfer/` 를
  남기지 않는다. `web/main/` prefix 만 검사하지만 남길 이유가 없다
- 기각: 릴레이 없이 `book` 도 heredoc(바이너리라 불가) / 릴레이 전용 버킷 신설(불필요 리소스)

### 2026-08-22 [10-1~4] Grafana 대시보드를 신판 채점 기준(book app)에 맞춤 — namespace 변수 + 기본값 `wskorea26`
- 근거: 2026-08-21 신판 채점지가 10-1~4 를 전부 `book app` 기준으로 본문에 명시했다(`mark.md:475-478`).
  구판에서 4패널을 전역으로 둔 근거였던 취합본 01 "All Pod" 문답은 `11-3` 을 가리키는데
  이 세트 채점지에는 11절이 없다. 정본 근거가 신판으로 더 세졌으므로 book app 쪽으로 정렬한다
- 채택: `templating` 에 `namespace` 쿼리 변수 1개, 4패널 expr 에 `namespace=~"$namespace"`,
  기본값 `wskorea26`. 대시보드를 열면 book app 파드만 보이고, All 로 바꾸면 전체 파드가 나와
  취합본 해석에도 클릭 한 번으로 대응된다. 당일 "네임스페이스별 필터" 문항이 붙어도 그대로 쓴다
- **`allValue: ".*"` 가 필수**다. All 선택 시 치환값이 변수 쿼리 결과가 아니라 리터럴 `.*` 가 된다.
  `includeAll` 만 두면 로드 시점에 `label_values(kube_pod_info, namespace)` 가 비었을 때
  `namespace=~""` 가 되어 4패널이 동시에 No data → 10-1~4 4점이 통째로 날아간다
- Pod 개수 stat(`id:3`)은 변수에 연결하지 않고 고정한다. 10-2-A 는 book app 개수 자체가 판정
  대상이라 필터 선택에 따라 값이 흔들리면 안 된다
- 정정: 2026-08-07 항목의 「`wskorea26-book-deploy` 는 과제지가 못 박은 이름」은 **사실이 아니다.**
  `task.md`·`mark.md`·`mark.sh`·`errata/` 어디에도 없고 `k8s/app/deployment.yaml:9` 에서 우리가 지은
  이름이다. stat 쿼리에서 `pod=~"wskorea26-book-deploy-.*"` 를 빼고 과제지가 명시한(`task.md:66`)
  `namespace="wskorea26"` 만 남겼다 — 이 ns 에는 book app 만 들어가므로 값은 같고 의존만 줄었다
- stat 패널에 `textMode: value_and_name` 과 `description` 을 넣었다. 숫자만 크게 뜨면 채점자가
  그 값이 book app 기준인지 알 수 없다
- 기본값 오염 없음: ConfigMap + grafana sidecar provisioning 이고 provider `allowUiUpdates` 가
  기본 false 라 UI 에서 저장해 파일을 덮어쓸 수 없다. 채점자는 항상 `wskorea26` 로 시작한다
- 대가: 채점 4점이 걸린 4패널 expr 을 건드렸다. 배포 리허설 때 상단 `Namespace: wskorea26` 표시와
  4패널 데이터, stat 숫자를 눈으로 확인한다 (실배포 검증은 대회 계정에서만 가능)

### 2026-07-27 k8s manifest 를 rendered/ 로 일괄 렌더 후 폴더 단위 apply
- 맥락: 파일별 인라인 Replace 파이프는 치환 누락·env 미선언을 조용히 통과시킴.
  치환 전 env 검사 + 치환 후 잔여 `${}` 검사를 넣으려면 렌더 결과가 파일로 남아야 한다.
- 채택: `<X>` 플레이스홀더를 `${ENV_VAR}`(env 변수명과 일치)로 통일, set-03 의 정규식
  렌더 패턴 재사용. k8s 전체를 `k8s/rendered/` 미러로 렌더 → `kubectl apply -R -f rendered/`
  한 번. helm values 는 kubectl 대상이 아니라 제외하고 `kps-values.rendered.yaml` 로 따로 렌더.
  Grafana 계정도 terraform output(`grafana_admin_user`/`grafana_admin_password`)으로 뽑아
  §1 에서 다른 값들과 한 번에 env 화 — 셸별 `$korea26!!` 이스케이프를 런북에서 제거.
- 기각: envsubst 단독(PS 미지원 + 미선언 변수를 빈 값으로 조용히 치환) → 사전 검사 필수.
  kustomize → 도구 추가 없이 폴더 apply + 번호 prefix 로 충분.
- 대가: grafana TGB 가 서비스(helm kps)보다 먼저 apply 됨 — LBC 가 재시도해 서비스 생성 후
  자동 바인딩되는 동작에 의존. 파일별 apply 순서 제어는 포기 (00- prefix 사전순으로 대체).
