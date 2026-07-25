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
  - **KMS 5키의 admin principal 은 배포자 IAM 신원뿐이다**(유의 10: 키 정책에 root·`kms:*` 금지).
    root 자격증명은 `data.tf` 의 `terraform_data.kms_admin_guard` precondition 이 plan 단계에서
    차단한다. 관리자 추가는 `kms_extra_admin_arns` 변수.
  - **이름 변수화는 절반만 돼 있다.** `name_prefix` 변수(기본 `wsc2026`)가 있지만 `vpc_name` 과
    서브넷 맵 키는 리터럴 `wsc2026-...` 이고, 보간을 쓰는 곳은 IGW/RTB/NAT 태그뿐이다.
    클러스터·테이블·ECR·Lambda 이름도 `variables.tf` 기본값이지 tfvars 항목이 아니다
    (tfvars 에는 `player_number`·`bucket_suffix` 둘뿐, 버킷 이름은 `data.tf` 에서 조합).
- 미해결:
  - **11-4 HighLatency 는 실발화가 불가능하다.** 제공 book 바이너리에 `/delay` 엔드포인트가 없다
    (로컬 실측 — 404, µs 응답). 채점 스크립트의 latency-gen 으로 평균 3초 초과를 만들 수 없다.
    채점 11-4 가 요구하는 5종 중 나머지 4종(PodHighCPU/PodHighMemory/PodNotReady/HighErrorRate)은
    부하 파드로 발화된다. `PodCrashLooping` 룰은 구현돼 있지만 채점 대상이 아니다.
  - **mark 5-5 오타 대응이 임시 상태다.** 채점지 5-5 가 클러스터를 `wsi2026-xxxxx` 형식으로 조회하는
    오류가 있어 저장소 `mark.sh` 를 `wsc2026-eks-cluster` 로 고쳤다. 마이스터넷 질의 답변 대기 중.
  - **메트릭 실명을 배포 후 다시 확인해야 한다.** README step 8 에서 `:2021/metrics` 를 grep 해
    `prometheus-rules.yaml`·`dashboard.json` 의 이름과 대조한다. aws-for-fluent-bit 이미지에
    `log_to_metrics` 가 없으면 upstream `fluent/fluent-bit` 최신 안정 태그로 교체한다.
  - **접두어가 30% 변동으로 바뀌면 `name_prefix` 만으로 안 끝난다.**
    `grep -rl wsc2026 terraform eksctl k8s app | xargs sed -i 's/wsc2026/<새접두어>/g'` 로
    terraform 까지 포함해 일괄 치환해야 한다. 라벨 키 `wsc2026/node` 도 이 범위에 든다.
  - **VPC CloudShell 홈은 세션 종료 시 삭제되고 업로드 UI 도 없다.** 재접속하면 README step 4
    셋업 블록을 통째로 다시 실행한다(멱등, 약 1–2분).
  - **coredns addon 을 업데이트하면 Corefile 이 초기화될 수 있다.** 업데이트하지 않는다.
    했다면 `k8s/01-coredns-wsc2026.yaml` 재적용 후 mark 4-1 grep 을 재확인한다.
  - 실측 소요시간 미기록.

## 채점 커버리지
<!-- mark.sh / mark/markN.sh 항목 대비 현재 구현이 어디까지 왔는지. -->

`mark.sh` 24항목(자동 22 + 수동 2). 항목별 구현 위치는 `docs/src/content/docs/setlist/set-03/task-1/mapping.md`.

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
- [x] 11-1 부하/장애 파드 생성 후 observability 파드 Running 수
- [x] 11-2 Grafana datasource 목록 + `wsc2026` 대시보드 검색
- [x] 11-3 (수동) 대시보드 Row 구성 + 로그 패널 형식
- [~] 11-4 (수동) 알람 5종 Firing — **4종만 가능**. HighLatency 는 `/delay` 부재로 실발화 불가

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거가 된다. -->

- terraform apply(1차):
- EKS 노드 준비:
- 기타 병목:

---
## 결정 로그
<!-- append만. 위 섹션과 달리 절대 수정하지 않는다. 최신이 위로 오게 쌓는다. -->

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
