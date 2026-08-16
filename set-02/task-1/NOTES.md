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
    (`mark.md:425-431`). 답변은 "동적 요청에 정상 수집되는지 검증"이라 실제로는 값 일치를 안 볼
    가능성이 높으나 채점지 문구는 그대로다. 실행 불가 조건이라 마감 전 질의 대상.
  - Monitoring 배점이 대분류 3.5(`mark.md:39`)와 세부 합 5(10-1~4)로 어긋난다. **원본
    `mark.pdf` 자체의 불일치**로 확인됐다(아래 2026-08-16 항목). 전사본은 양쪽 다 원본과
    일치하므로 손대지 않았다. 구현에는 영향이 없다(패널 4개 모두 구현).
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
| 9-1-A | `booking_id` 는 예시값, 고정 일치 아님 | 영향없음 | 구현·런북 어디에도 `booking_id` 하드코딩 없음 |
| 10-0 | Grafana 접속 게이트 신설 | 수정완료 | 채점지 `mark.md`·`mark.sh` 10절 교체. 접속 경로·계정은 `README.md:262-263`, `terraform/outputs.tf:76-78`과 이미 일치 |
| 10-1-A | book app CPU/Memory | 영향없음 | `dashboard.json:21,36` `sum by (namespace, pod)` — 범례에 book app 파드가 그대로 나온다 |
| 10-2-A | 실행중인 **book app** Pod 개수 | 수정완료 | `dashboard.json:52`가 클러스터 전역 합계라 book app 개수를 읽을 수 없었다. `namespace="wskorea26", pod=~"wskorea26-book-deploy-.*"` 로 한정 |
| 10-3-A | book app 재시작 횟수 | 영향없음 | `dashboard.json:67` 범례에 book app 파드 포함 |
| 10-4-A | book app 네트워크 수신량 | 영향없음 | `dashboard.json:82` 범례에 book app 파드 포함 |
| — | HighLatency Alert 채점 항목 **삭제** | 영향없음 | 저장소에 alert 룰이 애초에 없다 — `PrometheusRule` 파일 없음, `kube-prometheus-stack-values.yaml:17-18` `alertmanager.enabled: false` |
| — | 로그 `level` 필드 / 예외 로그 기준 | 미반영 | 이 세트 채점지에 로그 형식 채점 항목이 없다(`mark.md`·`mark.sh` 전문 확인). `task.md`에도 Reference02 로그 규격이 없다 |
| — | DataSource 이름 채점 | 미반영 | 이 세트 채점지에 DataSource 항목이 없다 |
| — | `static/ PASS` 객체 채점 제외 | 미반영 | 이 세트 2-2-A(`mark.md:159`)는 `web/main/` 2개 객체만 보고 `--prefix "static/"` 명령 자체가 없다 |
| — | `created_at` 을 `date` 기준 1분 이내 검증 | 미반영 | 이 세트 9-3-A 는 400 코드 확인이고, `created_at` 은 9-2-A 인데 판정이 "정확히 일치"라 기준이 다르다 (아래 미해결 참조) |
| — | 부하 Pod 생성 단계 이동 | 부분반영 | 이 세트엔 부하/crash 파드 manifest 자체가 없다. 유효한 부분은 5-4-A 각주 하나뿐이라 별도 파일 변경 없음 |

## 실측 소요시간

- terraform apply: (미실측)
- EKS 노드 준비: eksctl create cluster 약 20분 (README 기준)
- 기타 병목: CloudFront Deployed 전파 수 분

---
## 정정 로그
<!-- 과제지·채점지 정정과 그에 따른 구현 변경. 질의일·답변일·출처를 함께 적는다. 최신이 위로. -->

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

### 2026-08-16 [취합본] 번호 체계가 이 세트와 다름 — 취합본 단독 항목은 미반영
- 출처: `errata/질의답변-취합-20260816.txt` (심사장 공유 자료 기반 선수 취합본)
- 내용: 취합본은 Grafana 를 `11-1`·`11-3`, S3 KMS 를 `6-1`, 로그·Alert 항목을 별도 번호로 부른다.
  이 세트 채점지는 대분류 1~10 이고 Monitoring 이 10, 6-1-A 는 Lambda, S3 KMS 는 2-2-A 다
  (`mark.pdf` 원문 대조 — 배점열 `1,2,1.5,1,5,1,2.5,6.5,6,3.5` 합 30 이 `mark.md:39` 표와 일치).
  `1-1-A`·`2-1-A`·`5-4`·`7-2`·`[7] GSI`·`[10-1~4 (12)]` 만 이 세트 번호와 대응한다
- 판정: 취합본에만 있는 항목(`static/ PASS`, `9-3` date 기준, App Logs, DataSource, Alert Pod/sleep)은
  **미반영**. 대응 채점 항목이 이 세트에 존재하지 않아 반영할 대상 자체가 없다. 다른 판본 채점지가
  돌고 있다는 정황이므로, 대회 당일 배부본 번호가 11 까지 가면 이 판정을 다시 봐야 한다
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
  의존이 하나 더 붙는다. Pod 이름 prefix 는 Deployment→ReplicaSet→Pod 명명을 k8s 가 보장하고
  `wskorea26-book-deploy` 는 과제지가 못 박은 이름이라 더 안전하다
- 대가: Pod 개수 패널이 book app 전용이 되어 클러스터 전체 파드 수는 이 대시보드에서 안 보인다

### 2026-08-07 [2-1-A] S3 버킷명 비번호 채점 제외
- 답변일: 2026-08-07. 출처: `errata/질의 답변.txt:4-5`, `errata/질의 답변(1).txt:21-22`
- 판정: **수정완료(채점지 전사본만)** — 원본 채점지가 `<비번호>` 자리에 `103` 을 고정 기재해
  비번호가 103 이 아니면 오답 처리될 수 있었다. `mark.md` 의 리터럴을 `<비번호>` 로 되돌렸다.
  구현은 `terraform/data.tf:5` 가 `var.player_number` 를 붙이는 구조라 변경 없음

### 2026-08-07 [1-1-A] subnet-d prefix `/242` 오타
- 답변일: 2026-08-07. 출처: `errata/질의 답변.txt:1-2`
- 판정: **영향없음** — `terraform/variables.tf:37` 이 이미 `172.16.2.0/24`, `mark.md:114` 전사본도
  `/24` 다. 오타는 `mark.pdf` 원본에만 남아 있고 원본은 수정하지 않는다

### 2026-08-07 [7 / 4-1-A] DynamoDB GSI 요구사항 과제지 명시
- 답변일: 2026-08-07. 출처: `errata/질의 답변(1).txt:26-43`
- 판정: **수정완료(과제지 전사본만)** — Reference03 이 `concert_name` 조회·`created_at` 최신순
  정렬을 요구하는데 원본 과제지엔 PK `client_id` 만 있었다. `task.md` §7 에 GSI 줄을 추가.
  구현은 `terraform/dynamodb.tf:28-41` + `terraform/lambda/index.py:51-55`(`ScanIndexForward=False`)
  로 이미 반영돼 있었다

### 2026-08-07 [Alert] HighLatency 채점 항목 삭제
- 답변일: 2026-08-07. 출처: `errata/수정사항.txt:1-3`
- 내용: 지급 book 바이너리에 `/delay` 엔드포인트가 없어 정상 경로로는 HighLatency 를 fire 할 수
  없다는 질의에, 채점 항목 자체를 삭제하는 답변
- 판정: **영향없음** — 이 저장소는 alert 룰을 만들지 않는다. `alertmanager.enabled: false`
  (`k8s/monitoring/kube-prometheus-stack-values.yaml:17-18`) 는 요구 패널이 메트릭 시각화뿐이라는
  기존 결정의 결과이고, 이번 삭제로 그 결정이 그대로 유지된다

### 2026-08-07 [7-2-A] ALB 예상 출력은 최신 채점지 기준
- 답변일: 2026-08-07. 출처: `errata/질의 답변.txt:7-14`
- 판정: **영향없음** — 최신 기준 `wskorea26-cf` 2회 + `403` 이고, `mark.md:316-322` 전사본이 이미
  그 형태다. 구현도 헤더 조건 규칙 2개(`terraform/alb.tf:84-120`) + default 403(`:72-79`)

### 2026-08-07 [9-1-A] `booking_id` 는 예시값
- 답변일: 2026-08-07. 출처: `errata/수정사항.txt:12-13`
- 판정: **영향없음** — 고정값 일치가 아니라 동적 요청 처리 여부만 본다. 구현·런북에 `booking_id`
  하드코딩이 없다

---
## 결정 로그

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
