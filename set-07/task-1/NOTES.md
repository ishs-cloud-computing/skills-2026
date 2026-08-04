# set-07 / task-1

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.

## 현재 상태
<!-- 덮어쓴다. 코드와 어긋난 줄은 지우고 다시 쓴다. append 금지. -->

- 구성: terraform(단일 리전 종합 인프라) + eksctl(private cluster, Pod Identity) + k8s(app/logging/monitoring).
  머신 4분할 — 본 PC(PS7, terraform) / 일반 CloudShell(이미지 빌드) / SSM bastion(eksctl·helm·kubectl) /
  `unicorn-mark` CloudShell(채점).
- 미해결: 배포 실측 미수행 — apply·mark.sh 결과를 받으면 아래 채점 커버리지와 소요시간을 채운다.
- 미해결: 계정 root 로 운영할 때 EKS access entry 로 사후 보정이 되는지 미확인. 현재는 step 9 권한 게이트로
  bastion 삭제 전에 걸러내는 방식으로 회피한다.

## 채점 커버리지
<!-- mark.sh / mark/markN.sh 항목 대비 현재 구현이 어디까지 왔는지. -->

- [ ] 미실행 — `bash mark.sh` 결과 수신 후 항목별로 채운다.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거가 된다. -->

- terraform apply:
- EKS 노드 준비:
- 기타 병목:

---
## 정정 로그
<!-- 과제지·채점지의 오류/정정. task.pdf·mark.pdf 와 전사본 task.md·mark.md 는 원본 대조용으로 고치지 않는다. -->

### 2026-08-01 답변 (질의 ~2026-07-30 / 출처: `set-07/2026-08-01.txt`)

- **Platform MRK 리전**: 과제지 4번은 "us-east-1 다중 리전 키"라고 쓰여 있으나, 선수 유의사항 7(모든 리소스
  서울)이 우선이며 "Primary 를 서울에 두고 MRK 로 us-east-1 에서 쓸 수 있게 하라"는 뜻이라는 답변.
  → 구현 변경: 프라이머리를 ap-northeast-2 로, 레플리카를 us-east-1 로 뒤집었다(`terraform/kms.tf`).
- **Timezone**: 채점기준표 표기는 UTC 이나 **채점은 KST 기준**으로 확인한다(정정 2 재확인). 과제지는 KST 기준 풀이 지시.
  → 구현 변경: 아래 정정 2 항목 참조.
- 나머지(WAF override, GSI 문구)는 아래 2026-07-31 정정과 동일 내용.

### 2026-07-31 정정 4건 (출처: `set-07/task-1/1과제.txt`)

- **0) EKS Authentication mode 강제 삭제** — 직종협의회 결과로 "Access Entry 사용, aws-auth 미사용" 지문 삭제.
  → **구현 변경 없음.** 강제가 풀렸을 뿐 금지가 아니고, 채점 CloudShell 접근 경로는 그대로 필요하다.
  `eksctl/cluster.yaml` 의 `authenticationMode: API` + 생성자=채점 신원 전제를 유지한다.
- **1) 리소스 와일드카드 제한 해제** — 과제지 11 "와일드카드 액션 및 리소스" → "와일드카드 액션".
  → **구현 변경 없음.** `unicorn-audit-role` 은 이미 리소스 ARN 을 명시하고, 리소스 레벨 ARN 을 지원하지 않는
  `ec2:DescribeVpcs`/`eks:DescribeCluster` 와 KMS 키 정책에서만 `Resource:"*"` 를 쓴다. 이제 명시적으로 적법.
- **2) 채점 유의사항 18 추가** — "채점기준표에는 Timestamp 의 TZ 가 UTC 기준이나, 채점 시 KST 기준으로 확인".
  → **구현 변경 있음.** fluent-bit 이 UTC 를 강제하고 있었다. 아래 결정 로그 참조.
- **3) WAF rule-level override 허용** — "override action 은 모두 None, rule-level override 없이 적용" 삭제 →
  "필요할 경우 Custom Response 지정을 위해 override 가능, **채점 시 XSS 공격을 진행**함에 유의".
  → **구현 변경 있음.** 아래 결정 로그 참조.
- **4) GSI 문구에서 "Lambda를 통한 예약 조회를 지원하기 위해" 삭제** — 과제지의 논리 오류. 8-3/8-4 채점은
  side effect 우려로 `booking_id` 추출 방식을 유지한다는 답변.
  → **구현 변경 없음.** Lambda 는 PK `get_item` 이고 GSI 는 요구사항대로 존재만 하면 된다(채점 4-1-A).

---
## 결정 로그
<!-- append만. 위 섹션과 달리 절대 수정하지 않는다. 최신이 위로 오게 쌓는다. -->

### 2026-08-04 Platform MRK 프라이머리를 서울로, 타임스탬프를 KST 로, WAF XSS 룰에 Custom Response
- 맥락: 2026-07-31 정정 4건과 2026-08-01 답변을 현재 구현과 대조한 결과 세 곳이 어긋났다(위 정정 로그).
- **MRK 프라이머리 swap**: 채택 — 프라이머리 ap-northeast-2 + 레플리카 us-east-1. 유의사항 7 해석이 그렇고,
  채점 2-1-A 가 **서울에서** `alias/unicorn-kms-platform` 의 회전 상태를 읽는다. 회전은 프라이머리에만 설정
  가능하고 AWS 가 레플리카로 복사하는 구조라, 서울이 프라이머리면 `True 90` 이 값 그 자체가 된다.
  기각: 현행 유지(레플리카가 서울) → 복사된 `RotationPeriodInDays` 에 의존하고 유의사항 7 과도 어긋난다.
  대가: `platform_kms_primary_arn` output 을 `platform_kms_use1_arn` 으로 개명(미사용 output 이라 영향 없음).
  `platform_kms_arn`(eksctl·storageclass 치환용)은 이름 그대로라 런북은 안 바뀐다.
- **타임스탬프 KST**: 채택 — `reshape.lua` 를 `os.date("!...", sec + KST_OFFSET)` 로. 포맷(`...Z`)은 과제지
  그대로 두고 값만 KST. 과제지 예시가 근거다 — 앱 access 라인 `2026/06/09 06:16:16`(노드 KST 로컬시각)과
  기대 출력 `2026-06-09T06:16:16Z` 가 같은 값이다. 즉 기대값 자체가 KST 다.
  기각: 컨테이너에 `TZ=Asia/Seoul` 만 주고 `!` 제거 → tzdata 가 없으면 **조용히 UTC 로 돌아간다**.
  산술 오프셋은 실패할 여지가 없다. (한국은 서머타임이 없어 고정 +9 로 충분)
- **앱 컨테이너 시간대**: 채택 — 노드의 `/usr/share/zoneinfo/Asia/Seoul` 을 `/etc/localtime` 으로 hostPath 마운트.
  노드는 KST 지만 **컨테이너는 상속하지 않는다**. `created_at` 은 제공 바이너리가 만들어 확인이 불가능하므로,
  로컬 시각을 쓰는 구현이면 KST 가 되도록 걸어두는 보험이다(UTC 를 명시적으로 쓰면 손쓸 방법이 없다).
  기각: Dockerfile 에 `apk add tzdata` + `TZ` env → 요구사항 7(공개 취약점 0)에 패키지 하나를 새로 얹는다.
- **WAF XSS override**: 채택 — `AWSManagedRulesCommonRuleSet` 의 `CrossSiteScripting_*` 4종에
  `rule_action_override` 로 block + custom response(`unicorn-blocked`). 액션은 그대로 block/403 이라
  8-6-A(상태코드)는 영향이 없고, 차단 본문이 과제지 "차단 시 응답은 403, `Request blocked by Unicorn WAF`" 와
  일치하게 된다. 룰 이름은 변수 `waf_xss_rules` 로 빼 당일 벡터가 늘어도 목록만 고치면 된다.
  기각: 룰 전체를 Count 로 낮추고 별도 커스텀 룰로 차단 → 관리형 룰의 차단 능력을 우리 룰로 재구현해야 한다.
  CloudFront custom error response → 출제자가 "과제 의도에서 벗어난다"고 명시했다.
  대가: `KnownBadInputsRuleSet` 과 CommonRuleSet 의 나머지 룰은 여전히 기본 403 페이지를 반환한다.

### 2026-07-28 bastion 자격증명을 root 액세스 키에서 `aws login --remote` 로 전환
- 맥락: 채점은 root 로 하고(`mark.md` 순번 0 이 `rm -rf ~/.aws` 후 콘솔 세션 자격증명을 그대로 쓴다)
  private cluster 라 생성은 bastion 에서 해야 하므로, bastion 신원도 root 여야 한다. 그런데 런북은 그걸
  root 액세스 키로 맞추고 있었다. Organizations 멤버 계정에서 centralized root access management 가 켜져
  있으면 root 액세스 키 생성·복구가 차단돼 step 4 자체가 실행 불가가 된다.
- 채택: `aws login --remote`(AWS CLI 2.32.0+, 콘솔 자격증명 → 임시 크레덴셜). 얻는 신원은 액세스 키와 같아
  생성자=채점 신원 조건이 그대로 성립하고, 키 없이 콘솔 ID/PW 만으로 된다. `--remote` 는 브라우저 없는
  호스트용이라 SSM 세션에 맞는다. step 4 에 CLI 최신 v2 갱신과 `aws configure list`(TYPE=login) 확인을 넣었다.
- 기각: root 액세스 키 유지 → 키 생성이 막히면 대안이 없다.
  bastion 인스턴스 역할에 작업 권한 부여 → 생성자가 역할 ARN 이 되어 채점 셸(root)과 어긋난다.
  클러스터 생성 전에 채점 CloudShell 을 미리 띄워 ARN 을 대조하는 게이트 신설 → root 는 root 라 대조할
  모호함이 없다. `aws login` 직후 `get-caller-identity` 한 줄이면 같은 실수를 잡는다.
- 대가: CLI 2.32.0 의존(AL2023 기본 버전이 미달일 수 있어 설치 블록이 한 단계 늘었다), 세션 12시간 만료 시
  재로그인, signin 엔드포인트는 VPC Endpoint 가 없어 NAT 경유가 필수다.

### 2026-07-27 bastion 삭제 전 권한 게이트 + 상태 백업으로 복구 가능하게
- 맥락: step 10 이 bastion 을 지운 뒤에야 채점 셸에 kubectl 권한이 없다는 걸 알면 손쓸 방법이 없다.
  private cluster 라 VPC 밖에서는 클러스터에 접근조차 못 한다.
- 채택: "검증 → 백업 → 삭제" 순서 고정. step 9 끝에 채점 셸에서 `kubectl auth can-i '*' '*'` 게이트를 두고,
  step 10-1 에서 `~/.env` + `~/unicorn` 을 tgz 로 묶어 S3 경유로 본 PC 에 회수한 뒤 삭제한다.
- 기각: bastion 을 채점까지 남기기 → 보안 pillar·정리 차원에서 흔적을 남기고 싶지 않다.
  AMI/스냅샷으로 백업 → 리소스가 더 남고, 복구 가치가 있는 건 렌더 결과와 env 뿐이라 과하다.
- 대가: 백업 tgz 가 채점 대상 버킷(`_transfer/`)을 잠깐 경유한다. 최종 보관은 본 PC 이고
  10-2 마지막에 `_transfer/` 를 비우지만, **회수보다 정리를 먼저 하면 복구 불가**가 된다.

### 2026-07-27 자격증명을 "채점 셸과 같은 신원"으로 규정 (root 전제)
- 맥락: 런북이 `aws configure` 에 "선수 IAM 키"를 넣으라고 못박고 있었다. 대회가 root 사용을 금지하지
  않으면 선수는 root 로 운영하므로 실제와 어긋난다. 핵심은 키의 종류가 아니라
  클러스터 생성자 = 채점 CloudShell 신원이 성립하느냐다(`bootstrapClusterCreatorAdminPermissions`).
- 채택: 문구를 신원 일치 조건으로 바꾸고, 어긋났을 때를 step 9 게이트로 잡는다.
- 기각: 항상 전용 IAM 사용자를 만들게 강제 → 대회 지침에 없는 절차를 늘린다.
  access entry 사후 추가에만 의존 → CLI 레퍼런스가 STANDARD 항목에 "every IAM principal type" 을 허용한다고만
  하고 계정 root ARN 은 문서화돼 있지 않다. root 운영 시 이 경로가 보장되지 않는다.
- 대가: root 로 갔다가 게이트에서 걸리면 클러스터 재생성(약 20분)이 최선책일 수 있다.

### 2026-07-27 이미지 빌드를 본 PC → 일반 CloudShell 로 이전
- 맥락: step 2 가 본 PC 에서 `docker buildx build` 를 했는데, CLAUDE.md 대회 환경은 "Docker, WSL 사용 불가".
  셸만 PowerShell 로 옮겨서는 실행 자체가 안 된다.
- 채택: 일반 CloudShell(VPC environment 아님 — Docker·인터넷 egress 둘 다 필요)에서 빌드/푸시.
  재료(`Dockerfile`, `book`)는 이미 있는 S3 릴레이로 넘긴다.
- 기각: set-03 처럼 Actions → Upload file 수동 업로드 → 릴레이가 이미 있는데 수동 단계를 늘릴 이유가 없다.
  bastion 에 docker 설치 → private 서브넷이라 NAT 경유 pull + 인스턴스 타입 상향이 필요하다.
- 대가: 본 PC 의 `app/` 로 `book` 을 복사하던 단계가 사라져 로컬에서 이미지를 시험 빌드할 수 없다.

### 2026-07-27 placeholder 를 `${VAR}` 로 통일하고 k8s 를 rendered/ 일괄 apply 로 전환
- 맥락: eksctl 은 `${VAR}`, k8s 는 `<VAR>` 로 문법이 갈려 있어 검사 패스를 하나로 만들 수 없었다.
  파일별 `sed | kubectl apply -f -` 는 렌더 결과가 파일로 남지 않아 치환 누락을 조용히 통과시킨다.
- 채택: 전부 `${VAR}` 로 통일(변수명은 `~/.env` 에 이미 있는 이름에 맞춤 — 새 env 없음).
  k8s 는 `rendered/` 에 미러 렌더 후 `kubectl apply -R` 한 번. 치환 전 env 선언 검사 + 치환 후 잔여 `${}` 검사.
- 기각: envsubst 단독 → 미선언 변수를 빈 값으로 조용히 치환한다. python3 `expandvars` 는 `${VAR}` 를 그대로
  남겨 사후 검사에 걸리므로 방어가 한 겹 더 있다. gettext 설치를 추가하지 않아도 되는 것은 덤.
  kustomize → 도구를 늘리지 않고 폴더 apply + 번호 prefix 로 충분하다.
- 대가: `apply -R` 이 사전순이라 `app/serviceaccount.yaml` 을 `00-serviceaccount.yaml` 로 개명해야 했다
  (SA 가 Deployment 보다 먼저 와야 한다). 주석 안의 `${VAR}` 도 함께 치환돼 렌더 결과의 주석이 값으로 바뀐다.

### 2026-07-27 본 PC 단계만 PowerShell 7 로, 나머지는 bash 유지
- 맥락: 런북 318줄이 전부 bash 였다. 대회 PC 는 Windows 11 / PowerShell 7 이라 본 PC 단계가 실행되지 않는다.
- 채택: 셸을 머신에 맞춘다 — 본 PC(0·1·3·10)만 PowerShell, bastion·CloudShell 단계(2·4~9)는 실제 호스트가
  Linux 이므로 bash 그대로. 헤더에 `[본 PC·PowerShell]` / `[일반 CloudShell]` / `[bastion]` 라벨을 붙였다.
- 기각: 런북 전체를 PowerShell 로 → bastion·CloudShell 은 AL2023 이라 오답이다.
  set-02 식 전체 미러 README.linux.md → set-07 은 단계 대부분이 Linux 호스트라 중복만 커지고 드리프트를 부른다.
  set-03 식 delta-only(본 PC 단계만)로 갔다.
- 대가: 본 PC 단계를 고칠 때 README.md 와 README.linux.md 두 곳을 같이 고쳐야 한다(4개 step 한정).
