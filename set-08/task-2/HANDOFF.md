# set-08/task-2 세션 핸드오프

> 다음 에이전트가 컨텍스트를 복원하는 진입점. 상태가 바뀌면 이 문서를 덮어쓴다(append 금지).
> 내용 중복 금지 — 상세는 각 소유 문서로 포인터만. (README=런북, NOTES=함정·결정, docs/=설계 이유)
> **토큰 절약**: 이 문서 + 필요한 모듈 1개만 읽고 시작 가능하게 설계됨. 전체 재확인 불필요 — 아래 "완료됨" 표를 신뢰하고 해당 파일은 열지 마라.

## TL;DR

코드·문서 작업 끝났고, **2026-08-02 실 apply + CloudShell 실채점 리허설까지 완료**했다. 4모듈 20개 채점 항목 전부 기대 출력 일치(불일치 0), teardown 후 4개 리전 잔존 리소스 0 확인. 리허설에서 나온 런북 버그·개선점은 README/NOTES에 반영 완료.

- 실측 기록: [LOGS.md](LOGS.md) (항목별 증거·소요시간)
- 런북 개선점은 [README.md](README.md)와 [NOTES.md](NOTES.md)에 반영돼 있다.

남은 건 대회 당일 재실행뿐. 다시 apply하면 AWS 비용이 발생하니 사용자 확인 없이 시작하지 마라.

## 완료됨 — 재작업 금지 (파일 열어서 재검증할 필요 없음)

| 모듈 | 리전 | 구현 | plan | 커밋 |
|------|------|------|------|------|
| module-1-nosql | ap-northeast-2 | terraform 전체 + README×2 | 22 add / 0 err | `61f7b58` |
| module-2-lattice | ap-northeast-1 | terraform 전체 + README×2 | 24 add / 0 err | (이전 세션) |
| module-3-event-handling | ap-southeast-1 | terraform 전체 + README×2 | 16 add / 0 err | `026e183` |
| module-4-sqs-scaling | us-west-2 | terraform+eksctl+k8s + README×2 | 30 add / 0 err | (이전 세션) |

문서: NOTES.md 커버리지(4모듈 전부 `[~]`, 20/21 항목) + 결정 로그, docs setlist 4페이지, 루트 README 실행 순서까지 완료 (`a64247f`, `2655992`, `4963048`, `f7ac129`).

**빠른 상태 재확인 원커맨드** (이 문서가 stale한지 의심될 때만):
```bash
git log --oneline -5
grep -n "^| [0-9]" set-08/task-2/NOTES.md   # 모듈 현황 표 4행
```
출력이 위 표·커밋과 다르면 이 문서가 stale — 다시 작성.

## 다음 작업

1. ~~실 apply + 실채점~~ **완료(2026-08-02)**: 4모듈 배포·검증·CloudShell 채점·teardown 전부 수행. 결과는 [LOGS.md](LOGS.md), 런북 반영 내용은 [README.md](README.md)와 [NOTES.md](NOTES.md)를 참고.
2. **NOTES 커버리지 `[~]` → `[x]` 승격**: 실채점 증거는 확보됐으나 커버리지 표는 아직 `[~]`다. LOGS.md 항목별 증거를 근거로 승격할 것.
3. ~~협의회 예상 출력 파일 도착 시~~ **완료(2026-08-01)**: 공식 판정 기준 `provided/008_chall_2nd_patched_0801.md` 도착·대조 완료(불일치 0), 공식 diff `mark/mark2-{1..4}.sh` 적용 완료. 오류 정정 마감 2026-08-13 — 추가 오류 발견 시에만 게시판 질의.
4. **보류 항목 1건**: module-1~3(`-chdir`) vs module-4(`cd`) terraform 명령 형식 통일 — 다음 세트 런북에서 처음부터 통일.

## 새 작업 시작 전 필수 읽기 (스코프 좁혀서 — 전체 재독 금지)

1. 이 문서 (완료 상태 신뢰)
2. `NOTES.md` **함정 절만** grep (`^- \*\*` 패턴) — 결정 로그는 문제 생겼을 때만 참조
3. 작업 대상 모듈의 `mark/mark2-N.sh` 1개만 (채점 ground truth)
4. 작업 대상 모듈 `README.md` 1개만

task.md/mark.md 전체를 다시 읽지 마라 — 요구사항은 이미 코드·NOTES에 반영됨. 새 모듈 추가(협의회: 당일 최대 2개 추가 가능)나 요구사항 자체가 의심될 때만 원문 대조.

## 이 과제 고유 주의점 (요약 — 상세는 NOTES.md 함정 절)

- 과제지 명시 위반 감점 축: module-2 service-sg `0.0.0.0/0` 금지, Service EC2 Public IP 금지
- module-1: 지급 앱 상수(region·secret명·DB명·port)가 변수 변경 폭을 제한. TTL 인덱스 실동작 — dataset `sessions.expiresAt`(현재 2026-12-01~03)이 채점 시점보다 미래인지 확인
- module-3: 채점 3-5는 Lambda 직접 invoke — CloudTrail 전달 지연은 채점 무관. trail S3 버킷명 충돌 시 삭제 대신 `trail_name` 리네임
- module-4: 4-5 시점 pod 0개 감점 우려는 공식 예상 출력이 "4-6 결과 포함 판정"을 명시해 해소 확정. 런북 8단계는 SQS 재발송(6단계와 중복) 대신 경량 상태 확인으로 축소. 치환 placeholder cluster.yaml 7종/k8s 4종 — 가드 2단계 필수. helm 차트 미핀 — 당일 스키마 재확인
- 공통: 이름 충돌 시 삭제 금지 — 이름 변수 리네임으로 우회 (시행 후 유의사항 8, PowerUserAccess+Deny 가능성 있음)

## 환경 특이사항 (이 머신)

- Python은 `py` 런처만 동작 (`python`은 Store 스텁). PDF 재추출 시 페이지별 + `LAParams(line_margin=1.0)` + `py -X utf8`
- terraform 1.15.8 (mise), AWS 자격증명 로컬 존재 (plan 실행 가능)
- `docs/package-lock.json`에 무관한 로컬 수정 존재 — **스테이징 금지** (한 번 실수로 커밋됐다 `e767e74`로 되돌림 — `git add <특정파일>`만 쓰고 디렉터리 add 지양)
- PDF는 Git LFS. `provided/`는 원본 — 수정 금지, 참조만
