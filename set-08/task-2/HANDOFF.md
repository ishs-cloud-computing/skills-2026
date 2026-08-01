# set-08/task-2 세션 핸드오프

> 다음 세션의 에이전트가 컨텍스트를 복원하는 진입점. 상태가 바뀌면 이 문서를 덮어쓴다.
> 내용 중복 금지 — 상세는 각 소유 문서로 포인터만. (README=런북, NOTES=함정·결정, docs/=설계 이유)

## 상태 스냅샷 (2026-08-01, 2차)

- 브랜치: `set-08/task-2` (main 미병합, squash merge 예정)
- 구현: **모듈 4개 전부 완료** (module-1-nosql · module-2-lattice · module-3-event-handling · module-4-sqs-scaling)
- 검증 수준: `terraform fmt`/`validate`/`plan`까지 (module-1: 22 add, module-2: 24 add, module-3: 16 add, module-4: 30 add, 전부 0 errors).
  **실 apply·mark 실채점·CloudShell 검증은 미실행** — NOTES 커버리지가 전부 `[~]`인 이유.
- 설계/계획 문서: `docs/superpowers/specs/2026-08-01-set-08-task-2-design.md`, `docs/superpowers/plans/2026-08-01-set-08-task-2.md` (모듈 2·4 범위. 모듈 1·3 설계 근거는 docs setlist deployment.md와 NOTES 결정 로그가 소유)

## 다음 작업 (우선순위)

1. **실 apply + 실채점**: 모듈별 README 런북 순서대로. AWS 비용 발생 — 사용자 판단으로 시작. 채점은 CloudShell에서 `mark/mark2-N.sh` (CRLF 가드 필수). apply 실측 시간을 NOTES 실측 절에 기록.
2. **NOTES 커버리지 `[~]` → `[x]` 승격**: mark 실채점 통과 항목만.
3. **협의회 공식 예상 출력 파일 도착 시**: `mark.md`·NOTES 커버리지와 대조. 오류 정정 마감 2026-08-13 — 과제지·채점지 오류 발견 시 그 전에 마이스터넷 게시판 질의.

## 작업 전 필수 읽기 순서

1. 루트 `CLAUDE.md` (작업 규칙 — 특히 1·4·5번)
2. `task.md`·`mark.md` (요구사항·채점 원문)
3. `NOTES.md` — **결정 로그 기각안 먼저** (실패한 접근 반복 금지), 함정 절
4. 대상 모듈 `mark/mark2-N.sh` (채점 ground truth — 문서보다 우선)
5. 대상 모듈 `README.md` (런북)

## 이 과제 고유 주의점 (요약 — 상세는 NOTES.md 함정 절)

- 과제지 명시 위반 감점 축: module-2 service-sg `0.0.0.0/0` 금지, Service EC2 Public IP 금지
- module-1: 지급 앱 상수(region·secret명·DB명·port)가 변수 변경 폭을 제한. TTL 인덱스 실동작 — dataset `sessions.expiresAt`(현재 2026-12-01~03)이 채점 시점보다 미래인지 확인
- module-3: 채점 3-5는 Lambda 직접 invoke — CloudTrail 전달 지연은 채점 무관. trail S3 버킷명 충돌 시 삭제 대신 `trail_name` 리네임
- module-4: min 0 스케일 — 채점 직전 사전 활성화 (README 8단계, purge 금지). 치환 placeholder cluster.yaml 7종/k8s 4종 — 가드 2단계 필수. helm 차트 미핀 — 당일 스키마 재확인
- 이름 충돌 시 삭제 금지 — 이름 변수 리네임으로 우회 (시행 후 유의사항 8)

## 환경 특이사항 (이 머신)

- Python은 `py` 런처만 동작 (`python`은 Store 스텁). pdfminer.six·pyyaml 설치돼 있음 — PDF 재추출 필요 시 페이지별 + `LAParams(line_margin=1.0)` + `py -X utf8`
- terraform 1.15.8 (mise), AWS 자격증명 로컬 존재 (plan 실행 가능)
- `docs/package-lock.json`에 무관한 로컬 수정 존재 — **스테이징 금지**
- PDF는 Git LFS. `provided/`는 원본 — 수정 금지, 참조만
