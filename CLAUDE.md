# CLAUDE.md

2026 전국기능경기대회 클라우드컴퓨팅 직종의 과제를 Terraform / eksctl / Kubernetes manifest 로 관리하는 저장소.
1·2과제는 대회 전 약 10세트가 공개되며 이 중에서 출제된다. **구조만 통일하고 내용은 세트별로 채운다.**

이 파일은 **항상 로드되는 최소 규칙 + 라우팅 표**다. 배경·근거·절차는 아래 표에서 필요할 때 읽는다.
컨텍스트 레이어 전체 지도는 [`.claude/README.md`](.claude/README.md).

## 절대 규칙

깨지면 조용히 점수가 날아가거나 되돌릴 수 없는 것들. 상황과 무관하게 항상 적용된다.

1. **작업 전에 `task.md`·`mark.md`·채점 스크립트·`NOTES.md` 를 읽는다.** 결정 로그의 기각안을 먼저 봐 이미 실패한 접근을 반복하지 않는다. 트러블슈팅·마무리 전에도 같다.
2. **채점 스크립트가 정본이다.** 과제지 문장이 아니라 스크립트가 검사하는 정확한 형태를 기준으로 한다. 중복·불필요해 보여도 **채점 대상 필드는 제거하지 않는다.**
3. **리소스 이름은 과제지 명시 값과 정확히 일치.** 이름 정확 일치 채점 항목이 많다.
4. **`provided/`·`errata/`·`task.pdf`·`mark.pdf` 는 수정하지 않는다.** 정정 내용은 세트 `NOTES.md` 정정 로그에 기록한다.
5. **사전 제공 리소스를 지우거나 고치지 않는다.** 이름이 충돌하면 이쪽 이름 변수를 리네임해 우회한다. 계정에 명시적 Deny 가 붙어 있을 수 있다.
6. **`*.tfstate`·`.terraform/`·`outputs.json` 은 절대 커밋하지 않는다.** `apply` 는 본 컴퓨터에서만 한다.
7. **EKS 과제의 완료 조건은 "클러스터가 존재한다" 가 아니다.** 일반 CloudShell 에서 `aws eks update-kubeconfig --name <클러스터> --region <리전>` **한 줄** 뒤 `kubectl get nodes` 가 돼야 한다. 채점 중 그 외 명령은 허용되지 않는다.
8. **과제지가 요구하지 않는 bastion 은 감점 대상이다.** 3과제는 EC2 개수가 채점 축이라 아예 두지 않는다.
9. **바뀌기 쉬운 값은 변수로.** 이름·CIDR·리전·인스턴스 타입·개수는 `variables.tf` + `terraform.tfvars`.
10. **대회장에는 AI 보조가 없다.** 런북(`README.md`)이 유일한 보조 수단이므로 그대로 복붙 가능한 형태를 유지한다.
11. **런북 동결 — 2026-08-19 이후 런북을 수정하지 않는다.** 오류를 발견하면 조용히 고치지 말고 먼저 보고한다.

## 라우팅 — 상황별로 읽을 것

필요할 때만 연다. 미리 다 읽지 않는다.

| 상황 | 열 것 |
| --- | --- |
| 대회 구조·계정 권한·환경 제약을 모른다 | [`.claude/context/contest.md`](.claude/context/contest.md) |
| 새 세트/과제를 설계한다 | `/make-task <set-NN> <task-N>` → [`design.md`](.claude/context/design.md) · [`layout.md`](.claude/context/layout.md) |
| **과제지에 문항이 추가됐다 (당일 30% 변동)** | `addon-kit` 스킬 → [`QUICK-REFERENCE.md`](QUICK-REFERENCE.md) → [`KIT-INDEX.md`](KIT-INDEX.md) → `shared/addons/<kit>/README.md` |
| EKS 클러스터·인증을 건드린다 | [`.claude/context/eks-grading.md`](.claude/context/eks-grading.md) |
| 채점 항목을 어디까지 커버했는지 본다 | `grading-coverage` 스킬 |
| 이름이 과제지·채점지·구현에서 어긋나 보인다 | [`NAMING-AUDIT.md`](NAMING-AUDIT.md) — 어느 출처가 정본인지 세트별 판정 |
| AWS·k8s 인자/스키마를 모른다 | [`DOC-LINKS.md`](DOC-LINKS.md) — 리소스별 문서·로컬 스키마 명령 색인 |
| errata 를 반영한다 | `/errata <세트> <과제>` |
| 세트를 실제로 배포한다 (`init`/`plan`/`apply`·`eksctl create`·`kubectl apply`·`mark.sh`) | `set-XX/task-Y/README.md` 런북. 명령은 전부 거기 있다 |
| 배포가 깨졌다 | [`shared/TROUBLESHOOTING-COMMON.md`](shared/TROUBLESHOOTING-COMMON.md) → 세트 `NOTES.md` |
| 커밋·푸시한다 | `restore-placeholders` 스킬 (인프라 파일을 건드린 세션에서만) |
| 대회 당일 실행 절차 | [`DAY-OF.md`](DAY-OF.md) — 도착부터 채점 직전까지. **대회장에서는 이 컨텍스트 레이어가 로드되지 않는다** |

파일 종류별 규칙(`*.tf`·`k8s/`·`eksctl/`·`provided/`·`shared/addons/`·`set-*/task-*/`)은 [`.claude/rules/`](.claude/rules/) 가 **해당 파일을 열 때 자동으로 붙는다.** 미리 읽을 필요 없다.

## 협업

- 브랜치명: `set-09/task-1`, `fix-describe` 형식. 병합은 squash merge.
- 커밋 메시지: 영어 명령형.
- 새 소스 파일(`*.tf`·`*.yaml`·`*.py`·`*.sh`·`*.ps1` 등) 상단에 SPDX 헤더. **마크다운에는 붙이지 않는다.**

```
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
```

- 전체 기여 규약: [`CONTRIBUTING.md`](CONTRIBUTING.md)
