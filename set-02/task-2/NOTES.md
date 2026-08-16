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
| 4 | msk | ap-northeast-1 | 기본 iam 모드 실배포 미검증 (아래 결정 로그) |

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

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
- 대가: 기본 경로가 자체 바이너리에 의존한다. iam 모드 실배포 검증은 아직 없다 —
  9098 발행 실패 시 `producer_auth_mode=tls` 로 즉시 되돌릴 수 있게 두 경로를 모두 유지한다.
  이미 뜬 클러스터의 모드 전환은 리스너 in-place 업데이트(~15-30분)다.

### 2026-08-16 [module-4] 첫 배포 확인을 고정 대기 → 폴링으로
- 맥락: 런북이 "3~5분 대기 후 DynamoDB 확인" 이었다. producer user_data 는 kafka 다운로드,
  IAM jar, 토픽 생성 재시도(최대 5분), S3 바이너리 수신, systemd 기동을 차례로 하고 그 위에
  ESM 활성화가 겹친다 — 3~5분에 데이터가 없어도 정상일 수 있어 오진을 유발한다.
- 채택: ESM 2개가 `Enabled` 될 때까지, 그리고 DynamoDB item 수가 1 이상이 될 때까지 폴링하는
  루프를 PowerShell·bash 양쪽 런북에 넣었다(각 최대 10분). 실패 시 진입점은 SSM
  `send-command` 로 `systemctl is-active app` + 부팅 로그를 뽑는 비대화형 경로.
- 기각: 대기 시간만 늘리기(예: 10분 고정) → 빠르게 뜬 경우에도 그만큼 서게 된다.
- 함께: 정상 데이터만 보던 검증 절에 이상치 분기(S3 `alert/` 객체 + alert consumer 의
  `alert forwarded` 로그, 비면 sensor consumer 의 `ALERT -` 로그)를 PowerShell 런북에도 추가.
  기존엔 Linux 절에만 S3 한 줄이 있었다.
