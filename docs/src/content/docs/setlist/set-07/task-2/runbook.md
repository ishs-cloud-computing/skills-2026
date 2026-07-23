---
title: 배포 런북
description: 모듈별 배포 순서 요약 — 상세 명령은 저장소 모듈별 README 를 따른다
sidebar:
  order: 2
---

상세 명령은 저장소의 모듈별 README 가 단일 원본이다. 이 페이지는 실행 순서와 소요 시간만 요약한다.

| 모듈 | 런북 | 흐름 | 소요 |
|------|------|------|------|
| 1 | `set-07/task-2/module-1-nosql/README.md` | terraform apply → userdata 대기 → CloudShell 채점 | ~5분 |
| 2 | `set-07/task-2/module-2-cdn-function/README.md` | terraform apply(CF 배포 포함) → CloudShell 채점 | ~10분 |
| 3 | `set-07/task-2/module-3-eks-scaling/README.md` | terraform → bastion(eksctl ~20분 → 이미지 → KEDA/Karpenter → k8s) → CloudShell 채점 | ~40분 |
| 4 | `set-07/task-2/module-4-container-logging/README.md` | terraform → bastion(eksctl ~20분 → 이미지 → LBC → 앱 → Loki → OTel → Grafana) → CloudShell 채점 | ~45분 |

## 순서 제약

- 모듈 간 의존성은 없다 — 병렬 진행 가능. 시간이 부족하면 3·4(클러스터 생성 대기)를 먼저 시작한다.
- 모듈 3·4: bastion 에서 `aws configure`(선수 IAM 키) → `eksctl create cluster` 순서를 지킨다. 생성자 신원이 곧 채점 셸의 kubectl 권한이다.
- 모듈 3: helm(KEDA→Karpenter) → `10-karpenter-nodepool` → `20-deployment` 순서. NodePool 이 없으면 앱 Pod 가 Pending 으로 남는다.
- 모듈 4: LBC 설치 전에는 TargetGroupBinding 을 apply 할 수 없다(CRD 부재). Loki 설치 후 OTel 을 apply 한다.
