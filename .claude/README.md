# 에이전트 컨텍스트 레이어

Claude 가 이 저장소에서 일할 때 읽는 것들. **로드 시점에 따라 4층**으로 나눠져 있다.
층을 지키는 게 목적이다 — 항상 로드되는 층이 커지면 그만큼 매 턴 주의력이 희석되고, 정작 지금 필요한 규칙이 묻힌다.

| 층 | 위치 | 언제 로드되나 | 예산 |
| --- | --- | --- | --- |
| **0. 항상** | [`../CLAUDE.md`](../CLAUDE.md) | 모든 세션·모든 턴 | **~5KB 상한.** 절대 규칙 + 라우팅 표만 |
| **1. 경로 트리거** | [`rules/`](rules/) | frontmatter `paths:` 에 걸리는 파일을 열 때 | 파일당 ~1KB. 안 건드리면 0 |
| **2. 작업 트리거** | [`skills/`](skills/) | `description` 이 지금 작업과 맞을 때 | 시작 시 description 만(~100토큰), 본문은 발동 시 |
| **3. 명시 요청** | [`context/`](context/) · 루트 참고문서 | CLAUDE.md 라우팅 표를 보고 직접 열 때 | 상한 없음 |

## 0층 — `CLAUDE.md`

절대 규칙 11개와 라우팅 표. **여기에 배경·근거·절차를 다시 쓰지 않는다.**
새 규칙을 넣고 싶으면 먼저 물어본다: *깨지면 조용히 점수가 날아가나?* 아니면 1~3층이다.

## 1층 — `rules/` (경로 트리거)

```
terraform.md       **/*.tf **/*.tfvars **/*.tftpl
k8s.md             **/k8s/** **/*.yaml **/*.yml
eksctl.md          **/eksctl/**
provided.md        **/provided/** **/errata/** **/task.pdf **/mark.pdf
addons.md          shared/addons/**
task-notes.md      set-*/task-*/**
docs-style.md      set-*/task-*/**/*.md task-3/**/*.md shared/**/*.md
runbook-freeze.md  set-*/task-*/README*.md · 루트 참고문서 6종
```

**가장 싼 층이다.** 해당 파일을 안 건드리면 토큰이 0이다. 특정 파일 종류에서만 참인 규칙은 전부 여기로 보낸다.

## 2층 — `skills/` (작업 트리거)

| 스킬 | 발동 조건 |
| --- | --- |
| `addon-kit` | 문항이 추가됐다 · KIT 을 고르거나 만든다 |
| `grading-coverage` | 채점 스크립트 대비 커버리지를 대조한다 |
| `restore-placeholders` | 인프라 파일을 건드린 세션에서 커밋·푸시한다 |

`description` 이 곧 라우터다. **언제 쓰는지**를 트리거 표현(한국어 포함)까지 적어야 발동한다.

## 3층 — `context/` 와 루트 참고문서

| 파일 | 내용 |
| --- | --- |
| [`context/contest.md`](context/contest.md) | 대회 구조·지급 계정 권한·대회 환경·질의 창구 |
| [`context/design.md`](context/design.md) | 설계 순서·30% 변동·증설 여지·리뷰 체크리스트·완료 기준 |
| [`context/layout.md`](context/layout.md) | 디렉토리·파일 배치·문서 삼분할 |
| [`context/eks-grading.md`](context/eks-grading.md) | CloudShell 한 줄 조건·Access Entry·Pod Identity vs IRSA |

루트 참고문서(`DAY-OF.md`·`KIT-INDEX.md`·`QUICK-REFERENCE.md`·`DOC-LINKS.md`·`NAMING-AUDIT.md`)는 **사람이 대회장에서 쓰는 자료**다. 동결돼 있으므로 옮기거나 재구성하지 않는다 — 라우팅 표에서 가리키기만 한다.

## 나머지

- [`commands/`](commands/) — `/make-task`, `/errata`. 명시적으로 부를 때만.
- [`hooks/`](hooks/) — `terraform-check.sh` (PostToolUse: `.tf` 편집 시 `fmt` + `validate`, Windows 에서는 no-op).
- [`settings.json`](settings.json) — 훅 등록.

## 유지 규칙

1. **한 사실은 한 곳에만.** 두 층에 같은 내용을 쓰면 반드시 갈라지고, 갈라진 컨텍스트는 없는 것보다 나쁘다.
2. **가리키는 경로가 실재하는지 확인한다.** 없는 파일을 가리키면 에이전트가 찾아 헤매다 지어낸다.
3. **기한이 지난 규칙은 지우거나 지났다고 표시한다.** 만료된 지시가 항상 로드되는 층에 남아 있는 게 가장 비싸다.
4. 0층이 5KB 를 넘으면 무엇을 1~3층으로 내릴지 먼저 정한다.
