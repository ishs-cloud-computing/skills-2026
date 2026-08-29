---
paths:
  - "shared/addons/**"
---

`shared/addons/<kit>/` 는 당일 추가 문항을 기존 세트에 **복사(COPY)해 붙이는** KIT 이다. addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 세트 state 를 건드리지 않는다.

KIT README 가 지켜야 하는 형태 — 대회장에서는 AI 보조가 없으므로 **그대로 복붙 가능해야 한다**:

- `CHANGE` — 세트별로 채울 값. 꺾쇠 표기(`<기존>`·`<클러스터>`·`<이름>`)는 전부 치환 대상이며 하나라도 남으면 `validate` 에서 걸린다.
- 코드 블록 **머리에 붙일 `*.tf` 파일명**을 적는다.
- 블록 밑 `<details>` 에 세트별 항목(`outputs.tf` 보강 등).
- `VERIFY` — `shared/scripts/verify-kit.ps1 <kit>` 로 일괄 실행되는 형태.
- `## FAST` — terraform 없이 `aws` CLI 한두 줄로 끝나는 경로가 있으면 적는다. 대가는 state 와 실물이 어긋나는 것(그 세트를 더 apply 하지 않는다). 이름이 채점 대상인 IAM Role·Policy 와 생성 시에만 지정되는 속성에는 쓸 수 없다.
- 맨 아래 **막히면 여는 순서** — 실전 구현 → 로컬 스키마 명령 → [DOC-LINKS](../../DOC-LINKS.md#4-리소스별-색인).

KIT 을 새로 추가하면 [QUICK-REFERENCE.md](../../QUICK-REFERENCE.md) 의 꼬리 지시문 표와 [KIT-INDEX.md](../../KIT-INDEX.md) 역색인에 같이 등록한다. 등록되지 않은 KIT 은 당일에 못 찾는다.
