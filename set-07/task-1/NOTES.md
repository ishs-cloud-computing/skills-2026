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
## 결정 로그
<!-- append만. 위 섹션과 달리 절대 수정하지 않는다. 최신이 위로 오게 쌓는다. -->

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
