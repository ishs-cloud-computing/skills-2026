---
title: 2과제 개요
description: 8세트 2과제 — Small Challenges, 독립 모듈 4개
sidebar:
  order: 1
---

8세트 2과제 "Small Challenges"는 **독립 모듈 4개**(각 7.5점, 합계 30점)로 구성된다. 모듈마다 리전과 서비스 조합이 다르며 서로 간섭하지 않는다.

> **문서 유형** — 실행 절차(how-to)는 각 모듈 README(저장소 런북)를 따라간다. 각 선택의 이유는
> **[설계 근거](../deployment/)**·**[런북 설계 노트](../runbook/)**(explanation), 채점 항목 대조는 **[요구사항 ↔ 구현 매핑](../mapping/)**(reference)에 있다.

## 모듈 구성

| 모듈 | 주제 | 리전 | 핵심 서비스 | 상태 |
|------|------|------|-------------|------|
| 1 | NoSQL (DocumentDB) | ap-northeast-2 | DocumentDB + EC2 Client | 미착수 |
| 2 | VPC Lattice | ap-northeast-1 | EC2 ×2 + VPC Lattice | 구현 완료 (실채점 전) |
| 3 | Cloud Event Handling | ap-southeast-1 | EventBridge + Lambda + SNS | 미착수 |
| 4 | SQS Scaling | us-west-2 | EKS(Fargate) + KEDA(SQS) + Karpenter | 구현 완료 (실채점 전) |

이번 구현 범위는 **모듈 2·4**다. 모듈 1(NoSQL)·3(Cloud Event Handling)은 이번 문서에서 다루지 않는다.

## 모듈 2 — VPC Lattice 한눈에

주문 서비스를 Client/Service 두 EC2로 분리하고, 두 EC2 사이의 네트워크 연결(peering·TGW 등)을 만들지 않은 채 VPC Lattice로만 연결한다.

- **Client/Service VPC**: 각각 `10.61.0.0/16`·`10.62.0.0/16`, 서로 직접 연결 없음
- **EC2 ×2**: 지급 `client_app.py`(Public IP, :80)·`service_app.py`(Public IP 없음, :8080) 무수정 배포
- **VPC Lattice**: Service Network가 Client VPC에만 연결되고, Service의 Target Group이 Service VPC를 가리켜 두 VPC를 데이터 플레인 수준에서만 잇는다

## 모듈 4 — SQS Scaling 한눈에

SQS 큐 길이에 따라 KEDA가 Worker Pod를, Karpenter가 EC2 Worker Node를 스케일링한다. 컨트롤러(KEDA·Karpenter)는 Fargate에서, 실제 워커는 Karpenter EC2에서 구동한다는 점이 이 모듈의 핵심 제약이다.

- **EKS**: `skills-sqs-cluster`(us-west-2). Managed NodeGroup 없이 Fargate Profile 3개(keda·karpenter·kube-system)로 시스템 컴포넌트를 띄운다
- **SQS**: `skills-sqs-queue` — KEDA 트리거이자 지급 `worker.py`(Consumer)의 입력
- **KEDA**(ns `keda`): min 0 / max 6, queueLength 2 — 큐가 비면 워커 0개까지 축소
- **Karpenter**(ns `karpenter`): `skills-sqs-nodepool`/`skills-sqs-nodeclass`로 워커 전용 EC2 노드를 동적 프로비저닝
