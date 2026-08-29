---
name: addon-kit
description: Route an added/changed task requirement to one of the 37 prebuilt addon KITs under shared/addons/ and attach it to a set without disturbing existing resources. Use when a task sheet gains a new sentence or sub-question (the contest's 30% day-of variation), when asked "이 문항 어느 KIT이야", "추가 문항 붙여줘", "WAF/KMS/관측성 붙여야 해", when authoring or fixing a KIT under shared/addons/, or when a kit needs registering in QUICK-REFERENCE.md / KIT-INDEX.md. Not for building a set from scratch — that is /make-task.
---

# 추가 문항 → KIT 부착

당일 변동은 기존 문제 교체가 아니라 **문항 추가**다. 37개 KIT 이 이미 `shared/addons/` 에 있으므로 **새로 쓰지 말고 고른다.**

## 순서

1. **바뀐 문장에서 명사 하나를 뽑는다** (`WAF`·`TTL`·`액세스 로그`·`CMK`).
2. [`QUICK-REFERENCE.md`](../../../QUICK-REFERENCE.md) 의 꼬리 지시문 표에서 KIT 1개를 고른다. 30초 컷이다.
   갈림길(WAF 신규 vs 룰 추가, 로깅 4종, 지리적 제한 2종)이 헷갈리면 같은 파일 "헷갈리면" 절.
3. 세트별 사전 판정(이미 있음 / 신규 / 재생성)은 [`KIT-INDEX.md`](../../../KIT-INDEX.md) `#1과제-옵션-5개--세트별-사전-판정`.
4. **KIT README 를 연다.** `## FAST` 절이 있으면 A, 없으면 B.

| | **A · FAST** (14개) | **B · Terraform** (나머지) |
| --- | --- | --- |
| 절차 | `CHANGE` 값 채우기 → FAST 명령 → `VERIFY` | `CHANGE` → 코드 블록을 블록 머리에 적힌 `*.tf` 에 붙이고 `<기존>` 치환 → `<details>` 의 세트 항목(`outputs.tf` 보강) → `fmt`·`init`·`validate`·`plan` → `apply` → `VERIFY` |
| 시간 | 1~2분 | 5~15분 + 생성 대기 |
| 대가 | state 와 실물이 어긋난다 — 그 세트를 더 apply 하지 않는다 | 없음 |
| 못 쓸 때 | 이름이 채점 대상인 IAM Role·Policy, 생성 시에만 지정되는 속성 | — |

5. `VERIFY` 통과 뒤에만 세트 `mark.sh` 를 돌린다.

## 멈춰야 하는 지점

- `plan` 에 **기존 리소스 replace/delete 가 뜨면 apply 하지 않는다.**
- 이름이 충돌하면 기존 것을 지우지 말고 **KIT 쪽 변수를 리네임**한다.
- 1과제에는 **인프라 스케일링 문항이 없다.** 보이면 오독이다.
- 3rd-party Addon(Istio·Cilium·Calico·Crossplane·Nginx)·Helm 은 1과제 채점요소가 될 수 없다.

## KIT 이 2개 이상이면

하나씩 apply 하지 않는다. **전부 붙이고 `plan` 한 번**, replace/delete 0건 확인 후 apply.
선행 순서: `kms` → 암호화 인자를 쓰는 KIT · `cloudtrail-hardening` → `eventbridge-security-rules` · `waf` → `waf-extra-rules` · `observability` → `grafana-panels` · `cw-alarms` SNS 토픽 → 나머지 알람.
같은 파일이 겹치는 조합과 빼는 순서는 `KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때`.

`cluster.yaml` 을 건드리는 KIT 은 Terraform `plan` 에 안 잡힌다 — eksctl 쪽에서 따로 본다.

## 스크립트

```
shared\scripts\discover.ps1 -Region <리전>      # 실제 리소스 ID → addon.<리전>.env
shared\scripts\verify-kit.ps1 <kit> <kit>       # VERIFY 일괄 (KIT 부착한 terraform 디렉터리에서)
shared\scripts\foul-check.ps1                   # 제출 전 금지 조항·잔재 검사
```

## KIT 을 새로 만들거나 고칠 때

작성 규약은 [`.claude/rules/addons.md`](../../rules/addons.md) 가 `shared/addons/**` 편집 시 자동으로 붙는다.
**새 KIT 은 `QUICK-REFERENCE.md` 꼬리 지시문 표와 `KIT-INDEX.md` 역색인에 함께 등록한다.** 등록 안 된 KIT 은 당일에 못 찾는다.
