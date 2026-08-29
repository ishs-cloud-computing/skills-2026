---
name: grading-coverage
description: Cross-check a set's implementation against its grading script line by line and record the result in NOTES.md as a coverage table. Use when asked "채점 커버리지 대조", "mark.sh 다 만족해?", "빠진 채점 항목 있어?", "이 세트 리뷰해줘", before calling a task done, or after an errata patch. This is grading-item coverage, not code quality — for code-quality review use /code-review.
---

# 채점 커버리지 대조

채점은 **채점 스크립트가 검사하는 정확한 형태**가 기준이다. 과제지 문장이 아니라 스크립트가 정본이다.

## 입력

| 과제 | 채점 스크립트 |
| --- | --- |
| task-1 | `set-XX/task-1/mark.sh` |
| task-2 | `set-XX/task-2/mark/mark1.sh` ~ `markN.sh` (모듈별 개별 대조) |

같이 읽는다: `task.md`·`mark.md`(전사본) · `NOTES.md`(결정 로그의 기각안 — 이미 실패한 접근을 반복하지 않는다).

## 절차

1. 채점 스크립트에서 **검사 단위를 전부 뽑는다.** 스크립트가 실제로 읽는 것(리소스 이름·필드·annotation·응답 본문)을 항목으로 삼는다. 과제지 문장 단위로 자르지 않는다.
2. 항목마다 구현 파일의 근거 위치를 찾는다. 근거는 **파일 경로 + 해당 부분**이어야 한다.
3. `NOTES.md` 채점 커버리지 표를 갱신한다:
   - `[x]` 완료 · `[~]` 부분·조건부 · `[ ]` 미완
   - 각 항목 **한 줄 근거** 필수. "확인했습니다" 만 있고 경로가 없으면 미완으로 친다.
4. task-2 는 모듈 현황 표를 **모듈 수만큼** 채운다. 코드와 어긋나면 지우고 다시 쓴다(append 금지).

## 판정 기준

- 중복·불필요해 보여도 **채점 대상 필드는 제거하지 않는다.**
- 이름은 과제지 명시 값과 **정확히 일치**해야 한다. 어긋나 보이면 [`NAMING-AUDIT.md`](../../../NAMING-AUDIT.md) 에서 어느 출처가 정본인지 먼저 본다.
- EKS 항목은 리소스 존재가 아니라 **일반 CloudShell 에서 `aws eks update-kubeconfig` 한 줄 뒤 `kubectl get nodes`** 가 기준이다 → [`.claude/context/eks-grading.md`](../../context/eks-grading.md)
- 채점 스크립트가 SA 의 `eks.amazonaws.com/role-arn` annotation 을 읽으면 Pod Identity 는 무조건 미충족이다. IRSA 로 간다.

## 같이 도는 점검

[`.claude/context/design.md`](../../context/design.md#리뷰-체크리스트) 의 리뷰 체크리스트 — `fmt`/`validate`/`plan` 클린, 하드코딩, 과도한 IAM·`0.0.0.0/0` SG·평문 시크릿, 미사용 리소스, 런북 순서 일치.
제출 전 `shared\scripts\foul-check.ps1`.
