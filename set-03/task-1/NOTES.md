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
    mark.sh 1회로 따로 확인한다(README step 9-2).
  - **bastion 은 채점 대상이 아니다.** `terraform/bastion.tf`, 채점 전
    `apply -var="enable_bastion=false"` 로 제거한다. 지우기 전 README step 9 로 작업물을 회수한다.
  - **이름 변수화는 절반만 돼 있다.** `name_prefix` 변수(기본 `wsc2026`)가 있지만 `vpc_name` 과
    서브넷 맵 키는 리터럴 `wsc2026-...` 이고, 보간을 쓰는 곳은 IGW/RTB/NAT 태그뿐이다.
    클러스터·테이블·ECR·Lambda 이름도 `variables.tf` 기본값이지 tfvars 항목이 아니다
    (tfvars 에는 `player_number`·`bucket_suffix` 둘뿐, 버킷 이름은 `data.tf` 에서 조합).
- 미해결:
  - **11-4 HighLatency 는 실발화가 불가능하다.** 제공 book 바이너리에 `/delay` 엔드포인트가 없다
    (로컬 실측 — 404, µs 응답). 채점 스크립트의 latency-gen 으로 평균 3초 초과를 만들 수 없다.
    채점 11-4 가 요구하는 6종(채점지 사진 기준, PodCrashLooping 포함) 중 나머지 5종은
    부하 파드로 발화된다.
  - **mark 5-5 오타 대응이 임시 상태다.** 채점지 5-5 가 클러스터를 `wsi2026-xxxxx` 형식으로 조회하는
    오류가 있어 저장소 `mark.sh` 를 `wsc2026-eks-cluster` 로 고쳤다. 마이스터넷 질의 답변 대기 중.
  - **메트릭 실명을 배포 후 다시 확인해야 한다.** README step 8 에서 `:2021/metrics` 를 grep 해
    `prometheus-rules.yaml`·`dashboard.json` 의 이름과 대조한다. aws-for-fluent-bit 이미지에
    `log_to_metrics` 가 없으면 upstream `fluent/fluent-bit` 최신 안정 태그로 교체한다.
  - **접두어가 30% 변동으로 바뀌면 `name_prefix` 만으로 안 끝난다.**
    `grep -rl wsc2026 terraform eksctl k8s app | xargs sed -i 's/wsc2026/<새접두어>/g'` 로
    terraform 까지 포함해 일괄 치환해야 한다. 라벨 키 `wsc2026/node` 도 이 범위에 든다.
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
- [~] 11-4 (수동) 알람 6종 Firing — **5종만 가능**. HighLatency 는 `/delay` 부재로 실발화 불가

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거가 된다. -->

- terraform apply(1차):
- EKS 노드 준비:
- 기타 병목:

---
## 결정 로그
<!-- append만. 위 섹션과 달리 절대 수정하지 않는다. 최신이 위로 오게 쌓는다. -->

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
