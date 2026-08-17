# set-02 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 기본 4개. 당일 최대 6개까지 늘 수 있다. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 리전 | 미해결 |
|------|------|------|--------|
| 1 | workflow | ap-southeast-1 | 없음 |
| 2 | analytics | ap-northeast-2 | 없음 |
| 3 | event | eu-west-1 | 없음 |
| 4 | msk | ap-northeast-1 | TLS 단일 경로 실배포 미검증 — 2026-08-16 실배포는 (삭제된) iam 모드였다. 2026-08-17 자체 바이너리 제거 + TLS 고정, 결정 로그 참고 |

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

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

### 2026-08-17 [module-4] 자체 제작 producer 바이너리 완전 제거, TLS 단일 경로로 고정 (2026-08-16 결정 취소)
- 맥락: 2026-08-16 결정은 "`app/producer`(자체 제작 IAM 바이너리)가 저장소에 있으니 그걸 기본 배포로 쓴다"는 전제였다. 그 전제가 틀렸다 — **대회는 제공 바이너리(`provided/module4/app`) 외 배포를 허용하지 않는다.** 자체 제작 대체 바이너리를 대회 당일 EC2 에 올리는 경로 자체가 없고, 로컬 검증용으로라도 저장소에 남겨 두는 것 자체가 부적절하다(제작자가 배포하지 않은 산출물로 훈련·검증하지 않는다)
- 채택: `app/`(자체 제작 producer 바이너리 + README, LFS 추적) 를 저장소에서 완전히 삭제(`git rm -r`)하고 `.gitattributes` 의 `**/app/producer` LFS 규칙도 제거. terraform 의 `producer_auth_mode`/`iam_producer_binary_path` 변수 자체를 없애고 TLS 단일 경로로 하드코딩 — `msk.tf`(`unauthenticated = true` 고정), `security.tf`(9094 규칙 무조건 생성, count 제거), `s3.tf`(`local.app_source` 를 제공 바이너리 경로로 고정), `ec2.tf`(`app_bootstrap_servers` 를 `bootstrap_brokers_tls` 로 고정). `check-binary-auth.ps1/.sh` 는 바이너리가 아닌 진단 스크립트라 남기되, 대상을 제공 바이너리 재검증 용도로만 문구 수정. README.md·README.linux.md·BINARY-ANALYSIS.md 전체를 이 전제로 재작성(`terraform validate` 통과 확인, 2026-08-17)
- 기각: (1) iam 유지 + 대회 당일 수동 tls 전환 → 리스너 in-place 전환 15-30분이 들어 채점 시간 내 장애 대응 수단이 못 됨. (2) `app/producer` 를 로컬 검증 전용으로만 남기기(직전 결정) → 대회가 배포하지 않은 산출물은 애초에 저장소에 둘 이유가 없고, 남겨 두면 다음에 또 "이미 검증된 산출물이 있으니 기본으로 쓴다"는 동일한 오판을 반복할 위험이 있다
- 대가: 과제지 "IAM 인증을 통해서만 접근" 요구를 producer 실제 경로 기준으론 리터럴로 못 만족한다 — 제공 바이너리의 구조적 한계이며 우리가 고칠 수 없는 제약이다. 채점 스크립트 4-3 은 클러스터의 `Sasl.Iam.Enabled`(항상 true)만 보므로 채점 통과엔 지장 없다. 과제지 문구와 실제 배포 가능 경로가 어긋난다는 점은 질의 대상이나, 마이스터넷 질의 마감(2026-08-13)이 지나 이번 세트는 게시판 정정을 받을 수 없다 — 현재 코드 상태로 감수한다. IAM 경로 회귀 검증 수단(자체 바이너리)이 없어지므로, 필요하면 별도 스크래치 디렉터리에서 만들어 쓰고 저장소에는 커밋하지 않는다

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
