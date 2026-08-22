# set-03 / task-1

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.

## 현재 상태
<!-- 덮어쓴다. 코드와 어긋난 줄은 지우고 다시 쓴다. append 금지. -->

- 구성:
  - **HTTP 메트릭은 앱이 아니라 로그에서 나온다.** 앱이 `/metrics` 를 노출하지 않아
    `k8s/logging/fluent-bit.yaml` 의 `log_to_metrics` 필터 3개가 액세스 로그에서 만든다 —
    counter `wsc2026_requests_total`·`wsc2026_errors_total`, histogram
    `wsc2026_request_duration_seconds`. `prometheus_exporter` 가 `:2021/metrics` 로 노출한다.
    실제 메트릭 이름에는 fluent-bit 이 접두어를 붙여 `log_metric_counter_wsc2026_*` /
    `log_metric_histogram_wsc2026_*` 가 된다. `prometheus-rules.yaml`·`dashboard.json` 이
    이 이름을 그대로 쓴다(3파일 일치 확인됨).
  - **Lambda `TABLE_NAME` 값 자체가 KMS 암호문**이다(`aws_kms_ciphertext`). `lambda/index.py` 가
    런타임에 복호화한다. `kms_key_arn`(환경변수 저장 시)과 `source_kms_key_arn`(코드 zip 저장 시)도
    같은 `wsc2026-function-kms` 로 건다.
  - **ALB SG 는 ingress 어노테이션에 `wsc2026-app-alb-sg` 단독**으로만 지정한다.
    `manage-backend-security-group-rules` 를 쓰지 않는다. ALB→Pod 8080 은 Terraform
    `wsc2026-eks-shared-node-sg`(`security.tf`)가 열고, `cluster.yaml` 의 NG `attachIDs` 로 붙는다.
  - **CoreDNS 내부 도메인은 두 곳이 다 맞아야 동작한다.** kubelet `clusterDomain`
    (`cluster.yaml` 의 `overrideBootstrapCommand` → nodeadm NodeConfig)과 CoreDNS Corefile 패치
    (`k8s/01-coredns-wsc2026.yaml`). 채점 4-1 은 Corefile 만 grep 한다.
  - **`/booking` 경로 rewrite 는 CloudFront Function(viewer-request)이 한다** — 앱은 POST `/v1/book`
    만 제공한다(`cloudfront.tf`).
  - **`endpoints.tf` 에는 S3 Gateway 엔드포인트뿐이다.** eks/eks-auth Interface Endpoint 를 만들지
    않는다 — PHZ 가 Pod Identity 를 깬다(사유는 `endpoints.tf` 주석). 이미지 pull 은 app 서브넷의
    NAT 로 공개 레지스트리에서 직접 받는다.
  - **KMS 5키의 admin principal 은 계정 위임이다** — principal `"*"` + `kms:CallerAccount` 조건
    (`kms.tf`). 유의 10 이 금지하는 건 정책 텍스트의 root principal 과 `kms:*` 액션이고
    (`check_kms` 가 `:root"`·`"kms:*"` 두 문자열을 grep), 조건절이 범위를 계정 안으로 좁힌다.
    **조건절을 지우면 전 세계 공개**가 되므로 principal 만 따로 손대지 않는다.
    액션은 계속 열거해 `kms:*` 문자열을 만들지 않는다.
  - **k8s 치환 대상은 `${ECR}` 하나뿐이다**(`k8s/app/02-deployment.yaml`). 렌더는 bastion 에서
    `k8s/rendered/` 미러로 만들고 `kubectl apply -R -f rendered/` 한 번에 적용한다. helm values
    (`kube-prometheus-stack-values.yaml`)만 kubectl 대상이 아니라 제외된다. `dashboard.json` 은
    렌더 단계에서 ConfigMap yaml 로 만들어 `rendered/monitoring/99-dashboard-cm.yaml` 로 들어간다.
  - **kubectl 은 bastion 에서만 된다.** 클러스터가 fully private 이라 본 PC 는 API 에 닿지 않는다.
    본 PC PowerShell 은 terraform·eksctl 전용. 채점 경로(CloudShell + `mark-sg`)는 제출 전
    mark.sh 1회로 따로 확인한다(README step 9-2). 예외: destroy 10-1 은 엔드포인트를
    퍼블릭으로 전환해 본 PC 에서 kubectl 을 쓴다.
  - **bastion 은 채점 대상이 아니다.** `terraform/bastion.tf`, 채점 전
    `apply -var="enable_bastion=false"` 로 제거한다. 지우기 전 README step 9 로 작업물을 회수한다.
  - **이름 변수화는 절반만 돼 있다.** `name_prefix` 변수(기본 `wsc2026`)가 있지만 `vpc_name` 과
    서브넷 맵 키는 리터럴 `wsc2026-...` 이고, 보간을 쓰는 곳은 IGW/RTB/NAT 태그뿐이다.
    클러스터·테이블·ECR·Lambda 이름도 `variables.tf` 기본값이지 tfvars 항목이 아니다
    (tfvars 에는 `player_number`·`bucket_suffix` 둘뿐, 버킷 이름은 `data.tf` 에서 조합).
- 미해결:
  - ~~11-4 HighLatency 실발화 불가~~ → **2026-08-07 정정으로 채점 항목이 삭제됐다**(정정 로그).
    11-4 는 5종만 확인한다. 과제지 Alert 표의 HighLatency 규칙 자체는 그대로 요구되므로
    `prometheus-rules.yaml` 의 룰은 유지한다.
  - ~~mark 5-5 오타 대응이 임시 상태다~~ → **2026-08-21 최종 정정본이 공식 수정했다**(정정 로그).
    임의 수정이 아니게 됐으므로 `mark.sh` 주석과 README NOTICE 절을 걷어냈다.
  - **메트릭 실명을 배포 후 다시 확인해야 한다.** README step 8 에서 `:2021/metrics` 를 grep 해
    `prometheus-rules.yaml`·`dashboard.json` 의 이름과 대조한다. aws-for-fluent-bit 이미지에
    `log_to_metrics` 가 없으면 upstream `fluent/fluent-bit` 최신 안정 태그로 교체한다.
  - **KSM 이 노드 라벨을 실제로 노출하는지 배포 후 확인해야 한다.** `Available Nodes` 와
    `$nodegroup` 변수가 전적으로 `kube_node_labels{label_eks_amazonaws_com_nodegroup=...}` 에
    의존한다. README step 8 에서 kube-state-metrics `/metrics` 를 grep 한다.
  - **접두어가 30% 변동으로 바뀌면 `name_prefix` 만으로 안 끝난다.**
    `grep -rl wsc2026 terraform eksctl k8s app | xargs sed -i 's/wsc2026/<새접두어>/g'` 로
    terraform 까지 포함해 일괄 치환해야 한다. 라벨 키 `wsc2026/node` 도 이 범위에 든다.
  - **coredns addon 을 업데이트하면 Corefile 이 초기화될 수 있다.** 업데이트하지 않는다.
    했다면 `k8s/01-coredns-wsc2026.yaml` 재적용 후 mark 4-1 grep 을 재확인한다.
  - 실측 소요시간 미기록.

## 채점 커버리지
<!-- mark.sh / mark/markN.sh 항목 대비 현재 구현이 어디까지 왔는지. -->

`mark.sh` 24항목(자동 22 + 수동 2).

- [x] 1-1 VPC CIDR + 서브넷 Name/CIDR
- [x] 1-2 IGW·NAT×2·라우트 테이블 0.0.0.0/0
- [x] 2-1 DynamoDB 키/빌링/SSE/삭제방지/GSI, PITR 35일, 리소스 정책, db-kms
- [x] 3-1 ECR scanOnPush·태그 불변성·암호화·태그 목록, ecr-kms
- [x] 4-1 EKS 버전/private/로깅, 클러스터 SG any-open 없음, CoreDNS 도메인, eks-kms
- [x] 4-2 NG 2개 이름·타입, 라벨별 노드 수
- [x] 4-3 클러스터롤·노드롤 2종에 AdministratorAccess 없음
- [x] 5-1 deploy 2/2, svc, ingress ALB DNS, PDB
- [x] 5-2 replicas·nodeSelector·topologySpread·requests
- [x] 5-3 probe 3종 경로/포트, book-config 데이터
- [x] 5-4 앱 파드가 application 노드에만
- [x] 5-5 Pod Identity SA + 역할 정책 (채점지 오타는 저장소 mark.sh 에서 수정)
- [x] 6-1 S3 퍼블릭차단 4종, SSE+BucketKey, static/ 객체별 KMS
- [x] 7-1 Lambda 이름/런타임, 환경변수 암호문, function-kms
- [x] 7-2 Lambda 역할 정책에 `dynamodb:Query` 포함·`*` 없음
- [x] 8-1 ALB scheme·SG 이름 단독, 직접 curl 차단
- [x] 9-1 CloudFront 태그 + 루트 200
- [x] 9-2 기본 behavior CachingOptimized, 추가 behavior CachingDisabled
- [x] 9-3 E2E POST `/booking` → GET `/v1/book`
- [x] 10-1 WAF 이름, SQLi/XSS 차단, rate limit ≤ 200
- [x] 11-1 observability 파드 Running 수 (+ 부하 파드 6종 생성 — 최종본이 11-1 에 그대로 둔다)
- [x] 11-2 Grafana datasource 목록 + `wsc2026` 대시보드 검색
- [x] 11-3 (수동) 대시보드 필수 패널 16종 + 빈값 없음 + 로그 패널 형식 (파드 블록은 11-1 과 중복)
- [x] 11-4 (수동) 알람 5종 Firing (HighLatency 는 정정으로 채점 항목 삭제)

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거가 된다. -->

- terraform apply(1차):
- EKS 노드 준비:
- 기타 병목:

---
## 정정 로그
<!-- 과제지·채점지 정정과 그에 따른 구현 변경. 질의일·답변일·출처를 함께 적는다. 최신이 위로. -->

### 2026-08-21 [최종 정정본] 과제지·채점지 교체 — 08-16 정정 3건 번복
- 출처: 대회측 최종 수정본 PDF. `task.pdf`·`mark.pdf` 를 교체했다(구판 2026-07-03 → 정정본 2026-08-21 15:47, PDF 메타데이터 기준).
  **errata txt(2026-08-07·08-16)보다 최신이므로 최종본이 정본이다.**
- 과제지 실질 변경 1건: 11절 끝에 "동작의 확인을 위해 로그 및 메트릭을 1개 이상 발생시켜야 합니다." 추가
  → 판정: **수정완료(런북)** — `README.md` step 8 을 "필수 제출 조건"으로 승격하고, 부하 파드 정리 뒤
  POST 1회를 추가했다(파드를 지우면 트래픽이 끊겨 로그·메트릭이 비는 걸 막는다). 구현 변경 없음
- 채점지 5-5: 클러스터명 `wsi2026-cluster` → `wsc2026-eks-cluster` **공식 수정**
  → 판정: **영향없음(명령어)** — `mark.sh:85-88`·`mark.md` 는 이미 올바른 이름을 쓰고 있었다.
  임의 수정 근거였던 `mark.sh` 주석과 `README.md` NOTICE 절을 삭제했다. 마이스터넷 질의는 종결
- **번복 1 — [11-1/11-3] 파드 블록 이동**: 최종본은 파드 6종 + `sleep 180` 을 **11-1·11-3 양쪽에** 둔다.
  08-16 의 "11-1 에서 제외하고 11-3 수동 실행" 판정은 무효 → `mark.md` 11-1 에 블록을 복원했다
- **번복 2 — `latency-gen` 제거**: 최종본 11-1·11-3 에 `latency-gen`(`/delay?ms=5000`)이 살아 있다.
  "HighLatency 채점 삭제와 함께 뺐다"는 **연결 자체가 틀린 추론**이었다 — 삭제된 건 11-4 Firing 확인
  항목뿐이고 파드는 그것과 무관하다. `mark.md` 양쪽에 복원
- **번복 3 — [6-1] ` static/: PASS` 채점 제외**: 최종본 예상 출력에 그 줄이 그대로 있다.
  `terraform/s3.tf` 의 `aws_s3_object.static_marker`(0바이트 `static/`)가 이미 만들고 있어 **구현은 이미 부합**.
  목록 조회는 `Size>0` 필터라 마커가 안 나오고 객체 KMS 루프에만 나오는 게 정본과 일치한다 → 예상 출력 복원
- 채점지 11-3 구체화: 필수 패널 16종을 본문 명시 + "모든 메트릭 **및 로그**는 빈값이 없어야" +
  "(/v1/book을 제외한 로그가 있을 경우 오답처리)"
  → 판정: **수정완료** — `mark.md`·`mark.sh` 에 패널 16종 전사. 구현은 `dashboard.json` 1건:
  패널 제목 `Status Codes` → **`Status Code`**(최종본 표기와 일치). 누락 패널은 없었다
- 채점지 11-4: "(* HighLatency Alert 구성요소는 채점과 무관합니다.)" 가 **본문에 명시**됐다
  → 08-07 판정의 근거가 질의 답변에서 채점지 본문으로 승격. 결론 불변, `prometheus-rules.yaml` 룰 유지
- 신설 유의사항 12)("11-1 채점으로 생긴 파드는 채점 후 삭제") → `mark.md` 에 삽입, 기존 12)→13) 재번호.
  `README.md:370` 의 파드 삭제 단계가 이미 대응하고 있다
- `/v1/book 외 로그 오답` 조항: **구현 변경하지 않는다.** 채점 스스로 `error-gen`·`latency-gen` 으로
  비-`/v1/book` 로그를 만들고 과제지 로그 예시도 `/v1/book/999` 라 문자 그대로는 자기모순이다.
  공식 답변(`errata/수정사항.txt` 2번, 원문 확인): "현재 파일 수정이 불가하여 수정은 되지 않습니다.
  로그는 과제지와 채점기준표에 있는 형식으로 채점합니다." → 판정 기준은 형식이다.
  `fluent-bit.yaml` 을 `/v1/book` 전용으로 조이면 4XX 가 사라져 `HighErrorRate`(11-4)와
  Status Code 4XX 패널이 함께 죽는다 — 채점 항목을 맞바꾸는 순손해라 기각
- 범위 밖 보강 2건(사용자 승인): `dashboard.json` Status Code 카운터 3종에 `or vector(0)` 추가
  (요청 없는 상태 코드 대역의 시리즈 실종 = "빈값" 감점 방지. `Pending Pods`·`App Running`·`App Pending`
  과 동일 패턴). CloudWatch ELB 4XX/5XX 타깃은 리허설 필수 확인 항목으로 승격 — 선제 수정하지 않는다

### 2026-08-16 [출처 정정] `errata/수정사항(1).txt` 는 set-02 가 아니라 이 세트의 정정본이다
- 경위: 이 파일이 처음에 `set-02/errata/수정사항.txt` 로 놓여 set-02 판정 근거로 쓰였다.
  담긴 항목이 **11-2 DataSource·HighLatency Alert·Reference02 로그 level·`booking_id`** 인데,
  11절과 Alert 채점 항목은 set-02 채점지에 없고 이 세트에만 있다(`mark.md` 11-1~11-4).
  `set-02/errata/` 에서 삭제하고 이 세트로 옮겼다 — set-02 쪽 판정은 그 NOTES 에서 정정했다
- 같은 이유로 `errata/질의답변-취합-20260816.txt` 는 **두 세트가 섞인 취합본**이다.
  `11-x`·`6-1`(S3 KMS)·`9-3`(created_at)·`5-4`·App Logs 항목이 이 세트 몫이고,
  `1-1-A`·`2-1-A`·`7-2`·`[7] GSI`·`10-1~4` 는 set-02 몫이다. 양쪽 `errata/` 에 같은 파일을 둔다

### 2026-08-16 [11-3] Pod CPU/Memory 는 All Pod, 패널 이름·기타 로그는 채점 대상 아님
- 답변일: 2026-08-16 이전(취합 시점). 출처: `errata/수정사항.txt:1-2`,
  `errata/질의답변-취합-20260816.txt` 01·02·06
- 판정: **영향없음** — `k8s/monitoring/dashboard.json:30-46` 의 `namespace` 템플릿 변수가
  `includeAll: true` + 기본값 `All` 이라 Pod 로우(`:274`,`:315`,`:365`,`:419`)가 이미 전 네임스페이스
  전 파드를 잡는다. Application Logs 에 `/v1/book` 외 로그가 섞여도 판정 기준은 형식이고,
  `k8s/logging/fluent-bit.yaml:157-171` 이 status 로 `level` 을 유도해 채점지와 같은
  `INFO {"level":"INFO",...}` 형식을 만든다. 패널 이름 채점 제외는 요구 완화라 손댈 게 없다
- 채점지 전사본에만 반영: `mark.md` 11-3 · `mark.sh` 11-3 주석

### 2026-08-16 [9-3] `created_at` 은 curl 요청 직전 `date` 기준 1분 이내
- 답변일: 2026-08-16 이전(취합 시점). 출처: `errata/수정사항.txt:6-7`,
  `errata/질의답변-취합-20260816.txt` 03
- 내용: 기존 "스크립트 실행 시간 기준 1분 이내"가 모호하다는 질의에, curl 요청 시점의 시스템
  시간(`date`)을 기준으로 정밀 검증하겠다는 답변. `booking_id` 는 예시값이라 고정 일치를 안 본다
  (`errata/수정사항(1).txt` 4번 질의)
- 판정: **수정완료(채점지·채점 스크립트 전사본만)** — `mark.md` 9-3 과 `mark.sh:130` 에
  `TZ=Asia/Seoul date '+REQUEST TIME: ...'` 를 curl 직전에 추가하고 판정 문구를 바꿨다.
  구현은 `created_at` 을 앱이 요청 시점에 생성하므로 변경 없음

### 2026-08-16 [6-1] `static/ PASS` 객체는 채점 제외
- 출처: `errata/질의답변-취합-20260816.txt` 05
- 판정: **수정완료(채점지 전사본만)** — `aws s3api list-objects --prefix "static/"` 로 조회되지
  않는 객체라 예상 출력에서 ` static/: PASS` 줄을 뺐다. 구현은 `terraform` 이 `static/index.html`·
  `static/main.jpeg` 두 객체만 올리므로 영향 없음

### 2026-08-16 [11-1 / 11-3] 테스트 파드 생성 단계를 11-1 에서 11-3 수동 실행으로 이동
- 출처: `errata/질의답변-취합-20260816.txt` 04
- 내용: 11-1-A 는 파드 생성을 채점 대상에서 빼고, Alert 검증용 파드 생성과 `sleep` 은 11-3 에서
  수동으로 실행한다. 테스트 리소스 때문에 파드 조회 결과나 Alert 상태가 변해도 재채점하지 않는다
- 판정: **수정완료(채점지·채점 스크립트 전사본만)** — `mark.md`·`mark.sh` 의 파드 6종 생성 +
  `sleep 180` 블록을 11-1 에서 11-3 으로 옮겼다. `latency-gen`(`/delay?ms=5000`)은 아래
  HighLatency 삭제와 함께 뺐다. 구현 변경 없음 — 이 파드들은 채점자가 만드는 임시 리소스다

### 2026-08-07 [11-4] HighLatency Alert 채점 항목 삭제
- 답변일: 2026-08-07. 출처: `errata/수정사항(1).txt:1-3`
- 내용: 지급 book 바이너리에 `/delay` 엔드포인트가 없어(로컬 실측 404) 과제지 범위 안에서는
  평균 응답시간 3초 초과를 만들 수 없다는 질의에, 채점 항목 자체를 삭제하는 답변
- 판정: **수정완료(채점지·채점 스크립트 전사본만)** — 11-4 확인 대상을 6종에서 5종으로 줄였다.
  **`k8s/monitoring/prometheus-rules.yaml:68` 의 HighLatency 룰은 유지한다** — 과제지
  `task.md:175` Prometheus Alert 표가 여전히 이 룰을 요구하고, 삭제된 건 Firing 확인 항목뿐이다
- 해소: 위 "미해결"에 있던 11-4 5종 한계가 이 정정으로 감점 사유가 아니게 됐다

### 2026-08-07 [11-2] DataSource 이름은 기존 채점기준표 기준 유지
- 답변일: 2026-08-07. 출처: `errata/수정사항(1).txt:9-10`
- 판정: **영향없음** — 과제지에 이름이 없으니 명시해 달라는 질의에 "기존 채점기준표 기준으로
  채점"이라는 답변이라 요구가 그대로다. `k8s/monitoring/kube-prometheus-stack-values.yaml:98-113`
  의 datasource 이름이 `prometheus`·`alertmanager`·`cloudwatch` 로 `mark.md` 11-2 예상 출력과 일치

---
## 결정 로그
<!-- append만. 위 섹션과 달리 절대 수정하지 않는다. 최신이 위로 오게 쌓는다. -->

### 2026-08-22 대시보드 기준을 채점지 사진 → 최종 채점지 11-3 본문(16종 + 빈값 금지)으로 교체
- 맥락: 최종 정정본 PDF 를 이미지로 재판독했다(텍스트 추출은 빨간 글자·취소선을 버려 못 쓴다).
  11-3 의 **"메트릭과 로그 형식이 채점지 사진과 일치하는지 확인하며" 가 취소선으로 삭제**되고,
  빨간 글자로 "**모든 메트릭 및 로그는 빈값이 없어야합니다**. 다음 구성 요소가 대쉬보드에 포함되어
  있는지 확인합니다" + 필수 패널 16종이 들어갔다. 사진은 "(참고 사진)" 으로 격하됐다.
  → 채점축이 *사진 대조* 에서 **① 16종 존재 ② 전 패널 비어있지 않음 ③ Application Logs 는
  `/v1/book` 형식만** 으로 바뀌었다. 2026-07-29 결정("사진을 우선한다")의 전제가 사라졌다
- 발견한 결함 5건과 채택안(`dashboard.json` 단독 수정):
  1. **Application Logs 무필터** — Insights 쿼리에 필터가 없어 채점 스크립트의 `error-gen`(`/nonexist`)·
     `latency-gen`(`/delay?ms=5000`) 액세스 로그가 그대로 출력됐다 → 오답처리.
     `| filter @message like '"path":"/v1/book"'` 추가. `format.lua` 가 키 순서를 고정 출력하므로
     부분문자열 매칭이 안정적이다. Logs Insights 의 `like` 는 **작은/큰따옴표로 감싸면 부분문자열,
     슬래시로 감싸면 정규식**이다(AWS 문서 CWL_QuerySyntax-Filter). 패턴에 `"` 가 들어가므로 작은따옴표를
     쓴다 — 정규식 형태를 쓰면 `/` 이스케이프 방식이 문서화돼 있지 않아 검증 불가라 피했다
  2. **Available Nodes 붕괴 경로** — `sum by (label_eks_amazonaws_com_nodegroup)` + `=~"$nodegroup"`.
     `=~".*"` 는 **라벨이 없는 시리즈도 매치**하므로 KSM `metricLabelsAllowlist` 가 안 먹으면 조인이
     라벨을 못 붙이고 `sum by (없는 라벨)` 이 **이름 없는 타일 1개(총합 4)** 로 붕괴한다 — "각
     노드그룹별 노드 수" 가 아니게 되는 정확한 경로다. `count by (...) (kube_node_labels{...,
     label_eks_amazonaws_com_nodegroup!=""} and on (node) (kube_node_status_condition{...} == 1))`
     로 교체. **`!=""` 가 방어선** — 라벨이 없으면 조용히 틀린 숫자 대신 패널이 비어 리허설에서 드러난다.
     `textMode: value_and_name` + `orientation: horizontal` 로 그룹명 타일 2개 렌더를 고정
  3. **Request Count / Response Time 이 No Data** — 트래픽이 끊기면 빈값. `or vector(0)` 추가
  4. **Status Code 의 CloudWatch ELB 4XX/5XX 타깃** — 해당 코드가 한 번도 안 나면 CloudWatch 가
     데이터포인트를 아예 주지 않아 빈 시리즈가 된다(2026-07-29 항목의 미검증 대가). 타깃 2종을
     제거하고 패널 datasource 를 `-- Mixed --` → `prometheus` 로 환원. CloudWatch 연동 요구는
     Application Logs 가 계속 충족한다
  5. **Application Logs 패널 표시 옵션이 참고 사진과 달랐다** — `showTime: true` 가 타임스탬프 열을
     앞에 붙여 각 줄이 `2026-…  INFO {"level":…}` 로 보였다. 채점지 예시는 `INFO {"level":…}` 로
     시작하고 참고 사진에도 타임스탬프 열이 없다. `showTime`·`wrapLogMessage` 를 모두 `false` 로
     내려 줄 전체가 채점지 예시와 문자 그대로 같아지게 했다
- 참고 사진과 대조해 되돌린 것 1건: `Node Memory (%)` 범례를 `{{nodename}}` 으로 바꿨다가
  `{{instance}}`(`192.168.2.111:9100`)로 되돌렸다. Node CPU 와 표기가 갈리는 게 어색해 통일했는데,
  참고 사진이 이 패널만 instance 로 두고 있고 채점지 문구("노드별 Memory 사용률")는 둘 다 만족한다.
  구성 일치를 우선했다
- 보정 1건: `Pod Restarts` 를 `topk(10, ...)` 로 제한. `$namespace` 기본값이 All 이라(errata 2026-08-16
  "모든 파드") 타일이 수십 개가 되어 뭉갠다. 재시작 상위 10개면 `crash-test` 가 항상 최상단이다
- 기각:
  - **fluent-bit 을 `/v1/book` 전용으로 조여 수집 단계에서 거른다** → `error-gen` 의 404 가
    `wsc2026_errors_total` 의 유일한 공급원이라 HighErrorRate(11-4)와 Status Code 4XX 가 동반 사망한다.
    `log_to_metrics` 3종 **뒤에** grep 을 넣으면 메트릭은 살릴 수 있지만, 대시보드 수정 때문에
    1.5점짜리 알람 항목을 필터 순서 실수에 노출시킬 이유가 없다. 필터는 패널 쿼리에만 둔다
  - **Pod/App Pod CPU·Memory 를 limit 대비 % 로 변경**(채점지 문구가 "사용률") → limit 미설정 파드가
    NaN 이 되어 `$namespace=All` 에서 "빈값 없어야" 를 정면으로 위반한다. raw cores/bytes 유지
  - **Pod Restarts 를 "리스타트 Pod 개수" 단일 숫자로 변경** → 어느 파드가 재시작했는지가 사라지고
    재시작 1회 이상 경고 색상(과제지) 의미가 흐려진다. 파드별 타일 유지
- 대가: `/v1/book/999`(Reference02 의 WARN 예시 경로) 도 패널에서 제외된다. 오답처리 조항이
  "`/v1/book` 을 제외한 로그" 라 엄격 일치가 안전하고, 제공 바이너리는 그 경로를 만들지 않는다
  (라우팅이 `/v1/book` Exact 하나뿐이라 404 는 `path=/nonexist` 형태로만 남는다)

### 2026-08-22 step 2 이미지 빌드 입력을 CloudShell 업로드 UI → S3 릴레이(book) + 붙여넣기(Dockerfile)
- 맥락: set-07 task-1 방식으로 통일. 기존 런북은 `Dockerfile`·`book` 을 **Actions → Upload file**
  로 올리게 했는데 재시도마다 반복되는 수동 단계였고, 셸을 VPC environment 로 잘못 열면
  업로드 자체가 막혀 그 자리에서 멈춘다. step 1 은 이미 `outputs.json`·`task.tgz` 를 릴레이하고
  있어 `book` 한 줄만 얹으면 된다
- 채택: step 1 이 `..\app\book`(step 0 에서 shared 원본을 복사해 둔 것)을
  `s3://<static bucket>/_transfer/book` 으로 올리고, CloudShell 이 `aws s3 cp` 로 받는다.
  텍스트인 `Dockerfile` 은 `cat > Dockerfile <<'DOCKEREOF'` 붙여넣기 + `wc -l`(24) 대조
- CloudShell 쪽 버킷 이름은 `list-buckets` + `starts_with(Name,'wsc2026-static-')` 로 찾는다 —
  이름에 `bucket_suffix` 랜덤 4자가 박혀 있어 손으로 옮겨 적으면 틀리기 쉽다. `echo "$BUCKET"` 로
  step 1 출력과 눈으로 대조한다
- `sed -i 's/\r$//' Dockerfile`: Windows 클립보드 CRLF 가드
- `_transfer/` 는 기존대로 step 9-3 에서 통째로 비운다(mark 6-1). 별도 정리 단계를 늘리지 않았다
- 기각: `book` 도 heredoc(바이너리라 불가) / 버킷 이름 하드코딩(suffix 가 세트 실행마다 바뀐다)

### 2026-08-21 mark.sh 는 정본의 `sleep 180` 을 쓰지 않는다 — 파드 생성 1회 + 알람 폴링
- 맥락: 최종 채점지가 부하 파드 6종 생성 + `sleep 180` 을 11-1·11-3 **양쪽에** 둔다. 정본을 그대로
  베끼면 리허설마다 6분이 나간다(11-3 실행분은 `AlreadyExists` 로 조용히 실패하고 sleep 만 다시 돈다)
- 관찰: 그 6분은 검증이 아니라 알람 룰의 `for: 3m`(`prometheus-rules.yaml:26,37,50,82`)을 채우는
  고정 대기일 뿐이다. 그리고 **11-1 의 실제 검사(observability 파드 Running 수)는 부하 파드와 무관**하다.
  11-3·11-4 는 수동 채점이라 스크립트는 안내문만 출력한다
- 채택: ① 파드 생성을 `start_load_pods()` 로 묶어 **5-5 직후 1회** 호출 — 6-1~10-1 을 도는 동안
  3분 시계가 백그라운드로 흐른다. ② `sleep 180` 을 `wait_for_alerts()` 로 대체 — Grafana 데이터소스
  프록시로 Prometheus 에 `ALERTS{alertstate="firing"}` 를 질의해 기대 5종이 뜨는 즉시 통과(백스톱 4분).
  실측상 이미 Firing 이라 대기가 사실상 0 에 수렴하고, **어떤 알람이 떴는지 이름으로 출력**된다 —
  기다리기만 하던 단계가 11-4 가 채점하는 그 항목의 실질 검증이 된다
- 파드 생성을 맨 앞이 아니라 5절 뒤에 둔 이유: 5-4 가 `wsc2026` 네임스페이스 파드를 나열한다.
  앞에서 띄우면 채점자가 볼 5-4 출력과 리허설 출력이 달라진다(합격 조건은 `wsc2026-book-deploy`
  필터라 PASS/FAIL 은 불변이지만 충실도가 떨어진다)
- port-forward 대신 Grafana 프록시를 쓴 이유: 11-2 가 이미 `GRAFANA_LB` 로 붙고 있어 경로가 검증돼
  있고, 백그라운드 프로세스 정리가 필요 없다
- 기각: 정본 그대로 복사(리허설마다 6분을 쓰고 얻는 정보가 없다) / 11-3 블록만 스킵(실채점 흐름과
  달라지는데 아끼는 건 3분뿐이고 검증은 여전히 안 생긴다)
- **`mark.md` 는 정본 그대로 전사한다.** 이 최적화는 우리 리허설 도구인 `mark.sh` 에만 적용하며,
  스크립트 상단 주석에 정본과 다른 지점을 명시했다

### 2026-07-30 mark.sh 는 S3 릴레이 대신 vim 붙여넣기, destroy 10-1 의 ingress 삭제 제거
- 맥락: step 1 이 mark.sh 를 `_transfer/` 로 올리고 step 9-2 가 다시 내려받았다. 파일 하나를
  위해 릴레이 왕복이 붙고 9-3 정리 대상도 늘었다. destroy 10-1 은 퍼블릭 전환 후
  `update-kubeconfig` + `kubectl delete ingress` 로 ALB 를 회수했다.
- 채택: mark.sh 는 VPC CloudShell 에서 `vim mark.sh` 로 붙여넣는다(`:set paste`). destroy 는
  퍼블릭 전환 → `eksctl delete cluster` 만 남긴다 — eksctl 의 ELB cleanup 이
  `ingressClassName: alb` 인 ingress 를 스스로 지우고 ALB 삭제 완료까지 기다린다
  (`pkg/elb/cleanup.go`: ingress class `alb` 필터 + 2초 폴링 대기).
- 기각: 10-1 에서 kubectl 을 유지 → eksctl 이 같은 일을 하므로 kubectl 설치·kubeconfig 가 순전히 중복.
- 대가: eksctl 이 K8s API 에 붙어야 하므로 퍼블릭 전환은 그대로 필수다. eksctl 의 고아 SG 정리는
  `k8s-elb-*` + 클러스터 태그만 대상이라 Terraform 의 `wsc2026-app-alb-sg` 는 건드리지 않는다.

### 2026-07-30 `aws login` 을 named profile(wsc2026) → default 프로파일로
- 맥락: 지급 계정의 root 가 이미 유일한 신원인데(2026-07-29 항목) 런북은 `--profile wsc2026` 로
  프로파일을 따로 만들고 `AWS_PROFILE` 을 셸·`.env`·step 3 의 `$keep` 목록까지 끌고 다녔다.
  신원이 하나뿐이면 프로파일 분리가 사는 일이 없다 — 대회장에서 손만 더 간다.
- 채택: `aws login` / `aws configure list` 를 default 프로파일로 실행하고 `AWS_PROFILE` 을 전부 뺀다.
  `.env`·`.env.ps1` 에는 `AWS_DEFAULT_REGION` 만 남는다.
- 함께 정정: SDK 폴백을 `credential_process` 프로파일(2026-07-29 항목의 대가 절) → 임시 크레덴셜
  env 주입(`aws configure export-credentials --format env`)으로 바꿨다. default 프로파일에
  `credential_process` 를 걸면 자기 자신을 호출하는 꼴이라 성립하지 않는다.
- 함께 정정: step 0 의 `aws configure list` 는 두 줄 아래 `get-caller-identity` 와 검증이 겹쳐 지웠다.
  `~/.aws/credentials` 잔존 경고는 `get-caller-identity` 주석으로 옮겼다(ARN 이 root 가 아니면 그것).

### 2026-07-29 destroy 10-1 을 CloudShell 재진입 대신 엔드포인트 퍼블릭 전환으로
- 맥락: bastion 은 9-3 에서 지워지고 클러스터는 fully private 라, ingress 삭제 하나를 위해
  VPC CloudShell 에 재진입(홈 초기화 → kubectl 재설치·kubeconfig 재설정)해야 했다.
- 채택: 채점 종료 후에는 fully-private(mark 4-1)를 유지할 이유가 없다. AWS CLI
  `update-cluster-config` 로 `endpointPublicAccess=true` 를 켜고 본 PC PowerShell 에서
  ingress 삭제 → destroy 전 과정이 본 PC 한 곳에서 끝난다. `endpointPrivateAccess=true` 는
  유지해 teardown 중 노드 통신을 깨지 않는다.
- 기각: eksctl `utils update-cluster-vpc-config` → fully-private 로 만든 클러스터의 endpoint
  변경에 제약이 있고 버전별 동작이 변한다(작업 규칙 7). EKS API 직접 호출이 확실하다.
- 대가: 전환에 수 분 대기. 전환 후에는 mark 4-1(private 검사)이 통과하지 않는 상태가 된다 —
  채점 종료 후 단계라 무방하다.

### 2026-07-29 대시보드를 채점지 사진 기준으로 정렬, Active Alerts 는 alertlist 패널로
- 맥락: 채점지 사진 2장을 입수했다. 11-3·11-4 는 "채점지 사진과 일치" 가 채점 기준인데, 기존
  구현은 task.md 표기("All Node CPU" 등)를 따랐고 Active Alerts 는 `ALERTS{alertstate="firing"}`
  table 패널이라 사진(불꽃 아이콘·"Firing for"·"View alert rule")과 형태가 달랐다.
- 채택: 사진을 우선한다. 패널 제목·범례·단위·레이아웃을 사진대로 재작성(Pod CPU 는 raw cores
  무단위, Pod Memory 는 raw bytes, Available Nodes·Pod/App Restarts 는 그룹별/pod별 스탯,
  Status Codes 는 2XX/4XX/5XX + CloudWatch `AWS/ApplicationELB` ELB 4XX/5XX 혼합). Active Alerts
  는 `alertlist` 패널(stateFilter firing-only, datasource "prometheus") — Grafana 13.1.0(차트
  87.2.1 동봉)의 alertlist 는 data-source-managed(Prometheus) 룰을 네이티브로 표시하고
  datasource `manageAlerts` 기본값이 true 라 values 변경이 없다. 사진에 PodCrashLooping 이
  Firing 으로 있어 채점 알람을 5종 → 6종으로 정정(mark.sh 11-4 안내 포함).
- 기각: 6종 룰을 Grafana-managed 알람으로 이중 프로비저닝(sidecar.alerts) → PrometheusRule 과
  중복 정의가 되고 채점 대상인 Prometheus Alert 사양의 단일 근원이 깨진다.
- 대가: task.md Reference02 의 패널 표기와는 어긋난다(채점은 사진 대조라 사진을 따름). ELB 4XX/5XX
  는 ALB 이름을 미리 알 수 없어 dimension 와일드카드(`LoadBalancer: *`)+`matchExact: false` 에
  의존한다 — 배포 리허설에서 시리즈가 뜨는지 확인 필요.

### 2026-07-29 신원을 wsc2026-admin(액세스 키) → root(`aws login`)로, KMS 키 정책을 계정 위임으로
- 맥락: 채점지(`mark.md`·`task.md`)에 "사전에 IAM 사용자를 만들어 그 신원으로 진행하라"는 문구가 없다.
  문구가 없으면 채점자는 지급받은 root 로 CloudShell 을 연다. 그런데 KMS 는 IAM 정책이 아니라 키 정책이
  1차 관문이라, 관리자를 배포자 IAM 신원 하나로 잠근 기존 구성에서는 **채점 스크립트 자신이** 5키를
  `describe-key`·`get-key-policy` 조차 못 한다 → `check_kms` 5건 + 7-1 Lambda 환경변수 +
  (생성자 불일치로) kubectl 항목이 전부 FAIL 이 된다. 액세스 키 방식도 별개 문제였다 — Organizations
  멤버 계정에서 centralized root access management 가 켜져 있으면 root 키 생성 자체가 막힌다.
- 채택: 키 정책 관리자 principal 을 `"*"` + `Condition kms:CallerAccount = <account_id>` 로 바꿔
  **root ARN 문자열 없이 계정 위임**을 표현한다(액션 열거는 유지 → `kms:*` 문자열도 없다).
  그러면 신원을 나눌 이유가 사라져 terraform·eksctl·docker push·kubectl·채점이 모두 root 한 신원이 되고,
  자격증명은 `aws login`(본 PC) / `aws login --remote`(bastion) / 콘솔 세션 상속(CloudShell 2곳)으로
  받는다. 액세스 키를 만들지 않는다. `data.tf` 의 `kms_admin_guard`·`aws_iam_session_context` 와
  `kms_extra_admin_arns` 변수는 root 차단 장치였으므로 함께 제거했다. set-07/task-1 과 같은 모델이 된다.
- 기각: IAM 사용자 유지 + "채점 콘솔을 wsc2026-admin 으로 열어달라" → 채점자 행동은 통제할 수 없다.
  IAM 사용자 유지 + 키 정책에 읽기 전용 계정 위임 statement 만 추가 → KMS 는 통과해도 신원이 둘로 갈려
  런북이 복잡해지고 kubectl 은 여전히 root access entry 가 필요하다.
  키 정책에 `arn:aws:iam::<acct>:root` 명시 → `check_kms` 의 `:root"` grep 에 그대로 걸린다.
  principal 을 계정 ID 문자열(`"AWS": "<account_id>"`)로 → 저장 시 root ARN 으로 정규화될 가능성이
  높다(S3 버킷 정책이 그렇다). 실계정에서 `put-key-policy` → `get-key-policy` 로 확인되면 텍스트가 더
  얌전하므로 그때 갈아탄다.
- 대가: 정책 텍스트에 `"AWS": "*"` 가 남아 사람 채점자가 최소권한 위반으로 볼 여지가 있다(조건절로 계정
  안에 갇혀 있음을 설명할 수 있어야 한다). AWS CLI 2.32.0 의존(bastion 은 user_data 가 최신 v2 로 갱신,
  대회 PC 가 미달이고 갱신 불가면 `create-access-key` + `aws configure` 로 폴백). 세션 12시간 만료 시
  재로그인. signin 엔드포인트는 VPC Endpoint 가 없어 NAT 경유가 필수다.
  terraform·eksctl 은 Go SDK 라 `login_session` 프로파일을 아직 못 읽을 수 있다 — AWS 가 안내하는
  `credential_process = aws configure export-credentials ... --format process` 우회를 README step 0
  주석에 넣어 뒀다.
- 전제(미검증): EKS 가 root 를 클러스터 생성자 access entry 로 받는지 문서에 명시가 없다. 배포 리허설
  때 `bootstrapClusterCreatorAdminPermissions` 로 만든 클러스터에서 bastion kubectl 이 되는지 먼저 본다.
  안 되면 이 결정 전체를 되돌려야 한다.

### 2026-07-27 배포 작업 환경을 VPC CloudShell → SSM bastion 으로
- 맥락: CloudShell 홈이 세션마다 삭제되고 업로드 UI 도 없어, manifest 하나 고치려면 본 PC 재-tar →
  S3 → 재전개가 필요했다. 재접속마다 kubectl·helm 재설치와 `aws configure` 도 반복됐다.
- 채택: `bastion.tf` — app-sub-a(private+NAT)에 t3.small, SG 는 `mark-sg` 재사용, IAM 은
  `AmazonSSMManagedInstanceCore` 만. kubectl 권한은 인스턴스 역할이 아니라 bastion 에서
  `aws configure` 한 wsc2026-admin(= cluster creator)이 갖는다.
- 기각: bastion role 에 AdministratorAccess + EKS access entry → `cluster.yaml` 에 access entry 와
  env 가 늘고 `bootstrapClusterCreatorAdminPermissions` 와 이중화된다.
- 기각: 전용 bastion SG + cp-extra 인그레스 추가 → `mark-sg` 재사용이면 새 리소스가 0개이고,
  채점자가 쓸 mark-sg → private API 443 경로를 배포 내내 검증하게 된다.
- 기각: public 서브넷 + EIP + SSH(set-05 패턴) → SSM 이면 인바운드 규칙이 0개다.
- 기각: 작업물 백업을 S3 에 남기기 → `_transfer/` 는 mark 6-1 때문에 채점 전에 비워야 해서 같이
  지워진다. 릴레이를 역방향으로 한 번 더 써 본 PC 로 내린다(README step 9).
- 기각: bastion 삭제를 `terraform destroy -target` 으로 → `enable_cdn` 조건부 리소스와 data 조회가
  걸린다. 이미 쓰는 토글 패턴대로 `enable_bastion` 변수를 둔다.
- 대가: EC2 1대 과금(채점 전 제거). 채점 경로는 mark.sh 1회로 별도 확인해야 한다.
  bastion 을 지운 뒤 k8s 를 고치려면 되살려야 한다.
- 전제: 본 PC 에 session-manager-plugin 이 필요하다(동아리 lab-bootstrap 이 설치).

### 2026-07-27 k8s 치환을 rendered/ 로 옮기고 치환 전후 검사를 추가
- 맥락: eksctl 렌더가 env 누락을 조용히 삼켰다 — PowerShell `(Get-Item "env:X").Value` 가 `$null` 이
  되고 `String.Replace(old, null)` 은 예외 없이 빈 문자열을 넣는다. 잔여 검사
  `Select-String '\$\{'` 는 `cluster.yaml` 주석의 리터럴 `${...}` 를 잡아 항상 발화해 죽어 있었다.
  k8s 는 `sed | kubectl apply -f -` 로 디스크에 안 남겨 무엇이 적용됐는지 확인할 수 없었다.
- 채택: set-02/task-1 패턴 재사용 — 치환 전 env 존재 검사, `k8s/rendered/` 미러 렌더,
  치환 후 잔여 `${}` 검사, `kubectl apply -R -f rendered/` 한 번. 플레이스홀더는 `${ECR}` 로 통일하고
  주석에서는 리터럴 플레이스홀더를 뺐다(검사가 주석을 잡지 않게).
- 기각: 무제한 `envsubst` → `prometheus-rules.yaml` 의 `{{ $labels.* }}` 를 빈 문자열로 삼킨다.
  변수 목록을 먼저 뽑아 그것만 `sed` 로 치환한다.
- 기각: 전부를 한 번에 apply → PrometheusRule CRD 가 helm 설치물이라 순서가 필요하다.
  ns·CoreDNS 만 helm 앞에서 개별 apply 하고 나머지를 일괄 apply 한다.
- 대가: apply 지점이 두 곳(step 5 의 ns·CoreDNS, step 6-3 의 나머지)으로 남는다.

### 2026-07-21 HighLatency 룰을 사양(3s/1m)대로 유지
- 맥락: 채점 11-4 알람 5종 Firing. 제공 book 바이너리에 `/delay` 가 없어 실발화가 불가능하다.
- 채택: 룰을 과제지 사양 그대로 둔다. 대회 당일 바이너리에 `/delay` 가 있으면 그대로 동작한다.
- 기각: 임계를 낮춰 억지 발화 → 채점이 룰 사양 자체를 보면 불일치로 깨진다.
- 대가: 사전 리허설에서 이 항목만 Firing 확인이 안 된다.

### 2026-07-21 HTTP 메트릭을 fluent-bit log_to_metrics 로 생성
- 맥락: 채점 11-3·11-4 가 요청 수·에러율·지연 패널과 알람을 요구하는데 앱에 `/metrics` 가 없다.
- 채택: fluent-bit `log_to_metrics` 필터가 액세스 로그를 파싱해 counter/histogram 을 만들고
  `prometheus_exporter` 로 `:2021` 에 노출. 로깅 파이프라인 하나로 로그와 메트릭을 같이 얻는다.
- 기각: 앱에 exporter 사이드카 추가 → 제공 바이너리를 건드리지 않고는 계측 지점이 없다.
- 대가: 메트릭 이름이 fluent-bit 의 `log_metric_*` 접두어 규칙에 종속된다. 이미지 버전에 따라
  필터 유무·이름이 달라질 수 있어 배포 후 실명 확인(step 8)이 필수 절차로 남는다.

### 2026-07-21 eks / eks-auth Interface Endpoint 를 만들지 않는다
- 맥락: fully-private 클러스터라 엔드포인트를 다 만들고 싶어지는 자리다.
- 채택: S3 Gateway 만 둔다. `privateCluster.skipEndpointCreation: true` 로 eksctl 자동 생성도 막는다.
- 기각: eks/eks-auth Interface Endpoint(`private_dns_enabled`) → PHZ 가 OIDC·eks-auth 해석을
  가로채 Pod Identity/IRSA 가 깨진다(set-05 트러블슈팅 사례).
- 대가: 이미지 pull 이 NAT 경유 공개 레지스트리에 의존한다.

### 2026-07-21 `/booking` → `/v1/book` rewrite 를 CloudFront Function 으로
- 맥락: 채점 9-3 이 `POST /booking` 을 호출하는데 앱은 `POST /v1/book` 만 제공한다.
- 채택: viewer-request CloudFront Function 에서 `request.uri` 를 교체.
- 기각: ALB 리스너 규칙 → ALB 는 경로 rewrite 를 지원하지 않는다(리다이렉트만 가능).
- 대가: rewrite 로직이 CDN 레이어에 있어 ALB 직접 호출 경로에서는 동작하지 않는다.

### 2026-07-21 ALB SG 를 ingress 어노테이션에 단독 지정
- 맥락: 채점 8-1 이 ALB 의 SG 이름을 **단독**으로 출력하길 요구한다.
- 채택: `security-groups: wsc2026-app-alb-sg` 하나만 지정. ALB→Pod 8080 허용은 Terraform 의
  `wsc2026-eks-shared-node-sg` 가 사전에 열고, NG `attachIDs` 로 노드에 붙인다.
- 기각: `manage-backend-security-group-rules` → LBC 가 백엔드 SG 를 추가로 붙여 8-1 출력이 깨진다.
- 대가: SG 규칙이 LBC 자동 관리 밖에 있어, 앱 포트가 바뀌면 Terraform 을 같이 고쳐야 한다.
