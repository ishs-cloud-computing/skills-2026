# NAMING-AUDIT — 리소스 이름 오탈자·불일치 감사

과제지(`task.md`) · 채점지(`mark.md`) · 채점 스크립트(`mark.sh`·`mark/markN.sh`) · 제공자료(`provided/`) ·
구현(`.tf`·`.yaml`)에서 리소스 이름을 전부 추출해 네 출처를 교차 대조한 결과다.

**리소스 이름은 정확 일치 채점 항목이 많고**(CLAUDE.md Terraform 변수 규칙), 출제자는 게시된 과제 파일을
직접 고치지 않고 댓글·텍스트로 변경을 안내한다. 원문에 오타가 있어도 그대로 따르되 정본이 바뀌면 정본을
따르는 게 원칙이므로, **"어느 출처가 무엇을 뭐라고 부르는가"를 한곳에 모아둔다.**

- 감사일: 2026-08-22 · 대상: set-02 · set-03 · set-07
- 항목이 해소되면 해당 세트 `NOTES.md` 정정 로그로 옮기고 여기서 지운다.
- 세트별 설계 이력·기각안은 각 `set-XX/task-Y/NOTES.md`, 실행 절차는 `README.md` 를 본다.

## 총평

| 세트 | 원문 이름 문제 | 구현 ↔ 채점 스크립트 | terraform 하드코딩 |
|---|---|---|---|
| set-02 / task-1 | 5건 (표기 불일치 위주) | **일치** | 13줄 (전부 채점 비대상) |
| set-02 / task-2 | 7건 (**세 세트 중 최다**) | **일치** (module-3 은 합집합으로 흡수) | 10줄 (전부 채점 비대상) |
| set-03 / task-1 | 5건 | **일치** | 2줄 (둘 다 의도된 값) |
| set-07 / task-1 | 3건 (스펙 공백·저장소 예시값) | **일치** | **30+줄, 채점 대상 다수 — 최우선** |
| set-07 / task-2 | 1건 (유의사항 예시 복붙) | **일치** | 3줄 (채점 비대상) |

**구현이 채점 스크립트의 이름을 못 맞추는 건은 한 곳도 없다.** 남은 건 (a) 원문 자체의 표기 문제와
(b) 이름이 `.tf` 리터럴이라 정정이 와도 즉시 못 바꾸는 지점 두 가지다.

---

## set-02 / task-1 (`wskorea26-*`)

| # | 위치 | 내용 | 판정 |
|---|---|---|---|
| N1 | `task.md:135-138` Reference01 | IGW/NAT 만 `book-igw`·`book-ngw-c`·`book-ngw-d` 로 접두사가 `wskorea26-` 에서 벗어난다. 같은 표의 VPC·서브넷·RTB 는 전부 `wskorea26-` | **원문대로 유지.** 채점 1-2-A 는 이름이 아니라 `igw-…`/`nat-…` **ID** 만 읽는다. `variables.tf:46,52` 가 원문 그대로 |
| N2 | `task.md:167` ↔ `:169` | Lambda 경로가 표는 `/reserv-query`, 예시는 `/reserv_query` | **영향없음.** `alb.tf:84-118` 이 경로가 아니라 HTTP method 로 분기해 어느 쪽이 와도 통과 |
| N3 | `task.md` Reference02/03 | `concert_name` 예시값이 `2ND_TINY_CON`(Request) ↔ `2ND TINY_CON`(Response) ↔ `2ND%20TINY_CON`(쿼리)로 세 군데가 다르다 | **미해결.** 9-x E2E 는 채점자가 넣은 값을 그대로 되돌려주면 되므로 구현 영향은 없다 |
| N4 | `task.md:113` | "Distribution **Name**" 이라 적었지만 CloudFront 에 Name 속성이 없다. 채점은 **Comment** 로 조회(`mark.sh:9`) | **양쪽 방어.** `cloudfront.tf:41` comment + `:114` Name 태그 |
| N5 | `task.md` 전체 | ServiceAccount 이름을 과제지·채점지 어디에도 명시하지 않는다 | **자체 명명** `wskorea26-book-sa`. 채점 대상 아님 |

### 해소됨

- 구판 `mark.pdf` 1-1-A `172.16.2.0/242` → `/24` (2026-08-21 신판 취소선 정정)
- 구판 `mark.pdf` 2-1-A `wskorea26-concert-bucket-103` → `-<선수비번호>` (신판 수정)

### 하드코딩

| 파일:줄 | 리터럴 |
|---|---|
| `terraform/alb.tf:26,46,134` | `wskorea26-book-tg` · `wskorea26-lambda-tg` · `wskorea26-grafana-tg` |
| `terraform/iam.tf:28,36,54` | `wskorea26-book-app-policy` · `wskorea26-lbc-policy` · `wskorea26-fluent-bit-policy` |
| `terraform/security.tf:17,38,61,107` | `wskorea26-book-alb-sg` · `-grafana-alb-sg` · `-node-sg` · `-cluster-extra-sg` |
| `terraform/cloudfront.tf:12,20` | `wskorea26-book-rewrite` · `wskorea26-s3-oac` |
| `terraform/dynamodb.tf:29` | GSI `concert_name-created_at-index` (과제지 명시값) |

TG 3종은 채점이 이름을 직접 읽지는 않지만 ALB 규칙·TargetGroupBinding 이 물려 있어, 바꿀 때
`k8s/app/targetgroupbinding.yaml`·`k8s/monitoring/grafana-targetgroupbinding.yaml` 을 같이 고쳐야 한다.

---

## set-02 / task-2 (`wsc2026-*`)

| # | 모듈 | 위치 | 내용 | 판정 |
|---|---|---|---|---|
| N1 | 3 | `task.md:202-207`·`provided/module3/lambda.md` ↔ `mark/mark2-3.sh` | **이름 집합 자체가 다르다.** 룰: 과제지 `sg-change-rule`·`role-change-rule`·`ec2-terminate-rule`·`ec2-type-change-rule` ↔ 채점 `sg-ssh-rule`·`ec2-stop-rule`·`ec2-terminate-rule`·`required-tags-rule`. 함수: provided `sg-remediation`·`role-remediation`·`ec2-terminate-alert`·`ec2-type-remediation` ↔ 채점 `ec2-stop-remediation`·`ec2-terminate-alert`·`sg-remediation`·`tag-alert`. 겹치는 건 3개뿐이고 `sg-change-rule` ↔ `sg-ssh-rule` 은 **같은 룰의 이름이 다른 것** | **합집합으로 해소.** 함수 6·룰 6 을 `module-3-event/terraform/variables.tf:120-148` 의 map 으로 전부 생성. 어느 쪽이 정본이 돼도 map 값만 고치면 된다 |
| N2 | 4 | `mark.md:430` | 4-0 사전준비가 `BUCKET_NAME="wsc2026-student-score-bucket-(선수 비번호)"` — module-1 블록 복붙 | **채점 스크립트가 정본.** `mark/mark2-4.sh:7` 의 `wsc2026-sensor-alert-bucket-${NUM}` 이 맞고 구현도 그 이름. 질의 마감(2026-08-13) 이후라 정정을 받을 수 없다 |
| N3 | 4 | `mark.md:137` | 기대 출력에 `"S3_BUCKET": "wsc2026-student-score-bucket-103"` — 비번호 `103` 하드코딩 | **미해결.** set-02 task-1 2-1-A 와 같은 유형인데 그건 신판이 `<선수비번호>`로 고쳤고 이건 안 고쳤다 |
| N4 | 4 | `task.md:302-310` | §6 DynamoDB 속성표가 `studentId`·`examDate`·`korean/english/math/…` — module-1 학생점수 표 복붙. 바로 위 §6 Key 는 `sensorId`/`timestamp` | **Key 스키마가 정본.** `module-4-msk/terraform/dynamodb.tf:10,15` · `mark2-4.sh:14` 가 그 둘만 읽는다 |
| N5 | 4 | `task.md:270` | §3 MSK **Topic** 절 밑에 `- **PK** : sensorId` 가 붙어 있다. Kafka 토픽에 PK 개념이 없다 | **DynamoDB 절 잔재로 판정, 무시** |
| N6 | 3 | `task.md:176-181`·`:190` | 이 모듈의 네트워크만 `event-vpc`·`event-pub-a/b`·`event-pub-rtb`·`event-igw` 로 `wsc2026-` 접두사가 없다 | **원문대로 유지.** `variables.tf:18,43,49,69` 가 원문 그대로. 채점 비대상 |
| N7 | 2 | `DAY-OF.md:512` · `shared/addons/ec2-asg-alb/README.md:93` | `wsc2026-alaytics-ec2-role` 오타는 2026-08-21 신판이 고쳤고 전사본·구현 리네임도 끝났는데, **당일 치트시트가 아직 `alaytics` 를 "(과제지 오타 그대로)" 라고 지시**한다 | **저장소 stale — 고쳐야 한다.** 세 세트 통틀어 실전 리스크가 가장 큰 문서 오류 |

### 하드코딩

| 파일:줄 | 리터럴 | 비고 |
|---|---|---|
| `module-2-analytics/terraform/bastion.tf:8,31,41` | `wsc2026-analytics-bastion-sg`·`-role`·`-profile` | 과제지에 없는 작업용 리소스 |
| `module-4-msk/terraform/bastion.tf:9,19` | `wsc2026-msk-bastion-role`·`-profile` | 상동 |
| `module-4-msk/terraform/security.tf:11,67,109,135` | SG 4종 | 채점 비대상 |
| `module-3-event/terraform/config.tf:20` | `wsc2026-event-config-role` | 채점 비대상 (Config 룰 이름만 채점) |

채점 대상 이름은 전부 변수화돼 있다.

---

## set-03 / task-1 (`wsc2026-*`)

| # | 위치 | 내용 | 판정 |
|---|---|---|---|
| N1 | `task.md:77` ↔ `:85` | 노드그룹 접미사가 `wsc2026-addon-**nodegroup**` ↔ `wsc2026-workload-**ng**` 로 갈린다 | **양쪽 다 원문대로.** 채점지도 동일하다(`mark.sh:89,92`). 한쪽으로 통일하면 그 항목이 죽는다 |
| N2 | `task.md:44` | ConfigMap 만 `book-config` 로 `wsc2026-` 접두사가 없다. 다른 k8s 리소스는 전부 `wsc2026-book-*` | **원문대로 유지.** `mark.sh:116` 도 `book-config` 를 읽는다 |
| N3 | Reference02 ↔ 채점지 본문 11-3 ↔ 채점지 참고 사진 | Grafana 패널 제목이 **3중으로 갈린다.** 핵심 3건 — `Status Code`/`Status Codes`, `Alerts`/`Alert`, `App Restarts`/`App restarts`(소문자 r). 그 외 `All Node CPU` vs `Node CPU (%)` 등 대부분 패널이 어긋난다 | **미해결(구조로 흡수).** 채점지 본문 표기가 기본값. 당일 배부본이 다르면 `README.md:257` 의 `TITLES` 에 `"id":"새 제목"` 만 넣는다. 출처별 대응표는 `set-03/task-1/README.md:290` |
| N4 | `task.md:143` | "CDN **Name**" 이라 적었지만 CloudFront 에 Name 속성이 없다. 채점 9-1 은 **Name 태그**로 검색(`mark.sh:168`) — 같은 자리를 set-02 는 Comment 로 본다 | **양쪽 방어.** `cloudfront.tf:84` comment + `:170` Name 태그 |
| N5 | `task.md:52` | GSI 를 "booking_id 를 이용한 조회" 라고만 하고 **이름을 주지 않는다.** 로그 그룹 이름도 미지정 | **자체 명명.** GSI `booking_id-index`(`dynamodb.tf:30`), 로그 그룹 `/wsc2026/eks/book-app`(`cloudwatch.tf:12`). set-07 은 같은 자리를 명시한다 |

### 해소됨

- 구판 채점지 5-5 클러스터명 `wsi2026-cluster` → `wsc2026-eks-cluster` (2026-08-21 최종 정정본 공식 수정)

### 하드코딩

`var.name_prefix` 로 거의 전부 조립돼 있어 리터럴이 사실상 없다. 예외 2곳 모두 **의도된 값**이다.

| 파일:줄 | 리터럴 | 비고 |
|---|---|---|
| `terraform/dynamodb.tf:30` | GSI `booking_id-index` | N5 대로 이름 자유 |
| `terraform/security.tf:63,73` | SG `mark-sg` | 채점지가 `mark-sg` 를 그대로 쓴다(`mark.md:19-20`). **접두사를 붙이면 안 된다** |

---

## set-07 / task-1 (`unicorn-*`)

**세 세트 중 이름 정합성이 가장 좋다** — `unicorn-*` 이름 집합이 네 출처에서 완전히 일치하고 불일치 0건이다.

| # | 위치 | 내용 | 판정 |
|---|---|---|---|
| N1 | `mark.md:410` | ServiceAccount `unicorn-book-app-sa` 는 **채점지에만** 있고 `task.md` 는 이름을 주지 않는다 | **영향없음.** 기대 출력이 "출력되는 값이 있다면 정답" 이라 이름 자체는 미채점. 구현은 채점지 이름과 일치 |
| N2 | `mark.md` 예상 출력 다수 | 출제자 환경값이 그대로 박혀 있다 — `unicorn-web-837933860870`(계정 ID), `unicorn-monitoring-grafana-7974ccf57f-j585v`·`unicorn-monitoring-kube-pr-prometheus-0`(Pod 해시) | **유의사항 16(붉은 글씨만 채점)으로 커버.** 채점자가 문자열 비교를 하면 오답이 되므로 당일 확인 사항 |
| N3 | `shared/addons/cw-alarms/README.md:160-169` · `cw-dashboard/README.md:105,107` | 코드 블록이 `set-07/task-1/outputs.tf` 를 가리키는데 예시 출력은 `app/wskorea26-alb/…`(set-02 접두사)다. cw-dashboard 예시의 `wskorea26-alb`·`wskorea26-book-func` 도 set-02 실제 이름(`wskorea26-book-alb`·`wskorea26-book-lambda`)과 다르다 | **저장소 예시값 오류(경미).** 30% 변동 대비로 addon 을 급히 붙일 때 복붙하면 dimension 이 빈다 |

### 하드코딩 — 이 저장소 전체에서 가장 큰 미해결 건

작업 규칙 5(바뀌기 쉬운 축은 변수화)가 사실상 미적용이다. set-03 이 `var.name_prefix` 로 전부 조립하는
반면 이 세트는 **채점 대상 이름 대부분이 `.tf` 리터럴**이라, 당일 정정이나 30% 변동으로 이름이 바뀌면
파일을 일일이 열어야 한다.

| 우선 | 파일:줄 | 리터럴 | 채점 |
|---|---|---|---|
| **상** | `terraform/lambda.tf:38,68,74` | `unicorn-get-booking-func` · `-role` · `-policy` | 채점지 명시 |
| **상** | `terraform/dynamodb.tf:13,33` | `unicorn-concert-db` · GSI `client-id-created-at-index` | 채점지 명시 |
| **상** | `terraform/alb.tf:16,27,113,123` | `unicorn-alb` · `-tg` · `-grafana-alb` · `-grafana-tg` | 과제지 명시. 바꾸면 `k8s/app/targetgroupbinding.yaml`·`k8s/monitoring/grafana-targetgroupbinding.yaml` 동반 수정 |
| **상** | `terraform/waf.tf:14,84,120` | `unicorn-waf` · `-rate-limit` · `aws-waf-logs-unicorn` | 과제지 명시 |
| **상** | `terraform/kms.tf:36,71,154,168` | `alias/unicorn-kms-{app,data,platform×2}` | 과제지 명시 |
| **상** | `terraform/ecr.tf:13` | `unicorn-concert-app` | 과제지 명시 |
| **상** | `terraform/iam.tf:186,245` | `unicorn-audit-role` · `-audit-policy` | 과제지 명시 (9-2-A 가 ARN 을 직접 조립) |
| **상** | `terraform/cloudfront.tf:21,47` | `unicorn-alb-origin` · comment `unicorn-svc-cf` | 채점지 명시 |
| 중 | `terraform/iam.tf:35,56,63,80,87,105,112,117,128,159` | book-app·fluentbit·cwexporter·lbc·ebs-csi 역할/정책 8종 | 이름 비채점 |
| 중 | `terraform/security.tf:16,37,58,81,110,126` | SG 6종 | 이름 비채점 |
| 하 | `terraform/flowlog.tf:27,46` · `waf.tf:155` · `cloudfront.tf:13` | flowlog 역할·정책, delivery policy, OAC | 과제지에 없는 부수 리소스 |

권장: `variables.tf` 에 `name_prefix = "unicorn"` 을 두고 **"상" 구간만** 치환한다. "중/하" 까지 한 번에
건드리면 apply 검증된 구성을 미검증 상태로 만든다.

---

## set-07 / task-2 (`bigbae-` / `skillsphone-` / `skm-` / `o11y-`)

**네 출처의 이름 집합이 완전히 일치한다 — 불일치 0건.** 모듈별 접두사가 섞여 있지만 모듈 안에서는
일관되고 채점 스크립트와도 맞아 의도된 설계로 본다.

| # | 위치 | 내용 | 판정 |
|---|---|---|---|
| N1 | `task.md:28` | 유의사항 10)의 중괄호 축약 **예시가 `unicorn-subnet-pub-{a,b,c}`** 다. 2과제에는 `unicorn-*` 리소스가 존재하지 않는다 — 1과제 유의사항 복붙 | **영향없음.** 예시일 뿐 요구 리소스가 아니다. 이 세트에서 `unicorn` 이 나오는 유일한 줄 |

### 하드코딩

| 파일:줄 | 리터럴 | 비고 |
|---|---|---|
| `module-3-eks-scaling/terraform/iam.tf:15,34,83` | `skm-keda-policy` · `skm-app-sqs-policy` · `skm-karpenter-policy` | 과제지가 정책 이름을 지정하지 않는다. 채점 비대상 |

`module-1-nosql/terraform/dynamodb.tf` 의 속성명(`train_id`·`seat_id`·`user_id`·`reserved_at`·`event_id`)은
과제지 명시값이라 리터럴이 맞다.
