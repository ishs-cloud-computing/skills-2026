# set-08/task-2 세션 핸드오프

> 다음 세션의 에이전트가 컨텍스트를 복원하는 진입점. 상태가 바뀌면 이 문서를 덮어쓴다.
> 내용 중복 금지 — 상세는 각 소유 문서로 포인터만. (README=런북, NOTES=함정·결정, docs/=설계 이유)

## 상태 스냅샷 (2026-08-01)

- 브랜치: `set-08/task-2` (origin에 푸시됨, main 미병합, squash merge 예정)
- 구현: **module-2-lattice·module-4-sqs-scaling 완료**, module-1·module-3 미착수 (템플릿 디렉토리 상태)
- 검증 수준: `terraform fmt`/`validate`/`plan`까지 (module-2: 24 add, module-4: 30 add, 0 errors).
  **실 apply·mark 실채점·CloudShell 검증은 미실행** — NOTES 커버리지가 전부 `[~]`인 이유.
- 설계/계획 문서: `docs/superpowers/specs/2026-08-01-set-08-task-2-design.md`, `docs/superpowers/plans/2026-08-01-set-08-task-2.md`

## 다음 작업 (우선순위)

1. **module-1 (nosql, ap-northeast-2)**: DocumentDB + EC2 client(지급 `docdb_client.py`, systemd) + Secrets Manager + KMS. 지급파일 `provided/module-1/`, 채점 `mark/mark2-1.sh`. EC2 user-data 패턴은 module-2 `ec2.tf`+`userdata-*.tftpl` 재사용.
2. **module-3 (event-handling, ap-southeast-1)**: CloudTrail→EventBridge→Lambda(지급 `remediate_security_group.py`)→SNS. 채점 `mark/mark2-3.sh`. Lambda 배포는 set-07 module-1 `lambda.tf` 패턴 참조.
3. **실 apply + 실채점**: 각 모듈 README 런북 순서대로. 채점은 CloudShell에서 `mark/mark2-N.sh` (CRLF 가드 필수).

## 작업 전 필수 읽기 순서

1. 루트 `CLAUDE.md` (작업 규칙 — 특히 1·4·5번)
2. `task.md`·`mark.md` (요구사항·채점 원문)
3. `NOTES.md` — **결정 로그 기각안 먼저** (실패한 접근 반복 금지), 함정 절
4. 대상 모듈 `mark/mark2-N.sh` (채점 ground truth — 문서보다 우선)
5. 대상 모듈 `README.md` (런북)

## 이 과제 고유 주의점 (요약 — 상세는 NOTES.md 함정 절)

- 과제지 명시 위반 감점 축: service-sg `0.0.0.0/0` 금지, **Service EC2 Public IP 금지** (한 번 틀렸다 수정한 항목 — NOTES 결정 로그 참조)
- module-4는 min 0 스케일 — 채점 4-5가 4-6보다 먼저 배치를 조회하므로 **채점 직전 사전 활성화** (README 8단계, purge 금지)
- 치환 placeholder: cluster.yaml 7종 / k8s 4종 — README 렌더링 단계와 1:1, 가드 2단계 필수
- helm 차트 미핀 (KEDA 2.x·Karpenter 1.x 최신) — 작업 규칙 7: 사용 전 현재 스키마 재확인
- 협의회 추적: 공식 예상 출력 파일 도착 시 `mark.md`·NOTES 커버리지와 대조
- 보류 항목: sn_assoc SG ingress가 `client_port` 사용 (의미상 `listener_port`가 정확하나 둘 다 기본 80 — 변수 분리 시 함께 수정)

## 환경 특이사항 (이 머신)

- Python은 `py` 런처만 동작 (`python`은 Store 스텁). pdfminer.six·pyyaml 설치돼 있음 — PDF 재추출 필요 시 페이지별 + `LAParams(line_margin=1.0)` + `py -X utf8`
- terraform 1.15.8 (mise), AWS 자격증명 로컬 존재 (plan 실행 가능)
- `docs/package-lock.json`에 무관한 로컬 수정 존재 — **스테이징 금지**
- PDF는 Git LFS. `provided/`는 원본 — 수정 금지, 참조만
