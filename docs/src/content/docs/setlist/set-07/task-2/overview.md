---
title: 2과제 개요
description: 7세트 2과제 — Small Challenge, 독립 모듈 4개
sidebar:
  order: 1
---

7세트 2과제 "Small Challenge"는 **독립 모듈 4개**(각 7.5점, 합계 30점)로 구성된다. 모듈마다 리전과 서비스 조합이 다르며 서로 간섭하지 않는다.

> **문서 유형** — 실행은 **[배포 런북](../runbook/)**(how-to)을 따라간다. 각 선택의 이유는
> **[설계 근거](../deployment/)**(explanation), 채점 항목 대조는 **[요구사항 ↔ 구현 매핑](../mapping/)**(reference)에 있다.

## 모듈 구성

| 모듈 | 주제 | 리전 | 핵심 서비스 | 상태 |
|------|------|------|-------------|------|
| 1 | NoSQL | ap-southeast-1 | DynamoDB(Streams·GSI) + Lambda + EC2 | 구현 완료 |
| 2 | CDN Function | us-east-1 | S3 + CloudFront Functions + KVS | 구현 완료 |
| 3 | EKS Scaling | ap-northeast-2 | EKS + KEDA(SQS) + Karpenter | 구현 완료 (실채점 전) |
| 4 | Container Logging | ap-northeast-1 | EKS + OTel + Loki + Grafana | 미착수 |

## 모듈 1 — NoSQL 한눈에

BigBae Trains 기차 티켓 예매 시스템. Terraform 단일 apply로 끝난다 (EKS 무관).

- **DynamoDB**: 예약 테이블(`train_id`/`seat_id`, Streams NEW_AND_OLD_IMAGES, PITR, sparse GSI `gsi-user-reservations`) + 감사 테이블(`event_id`)
- **Lambda**: Streams 트리거로 예약 변경을 감사 테이블에 적재 (`python3.13`, 지급 `lambda.py` 무수정)
- **EC2**: 지급 Flask 앱(`app.py`)을 systemd로 :8080 서빙, 조건부 쓰기(409)와 GSI 조회 API 제공

## 모듈 2 — CDN Function 한눈에

SkillsPhone 랜딩 페이지의 엣지 A/B 테스팅. Terraform 단일 apply로 끝난다 (서버·컨테이너 없음).

- **S3**: 지급 `index_a/b.html`을 `version-a/`·`version-b/` 경로에 호스팅, Public Access 전면 차단 + OAC 정책
- **KeyValueStore**: 노출 비율(`weight=0.3`)과 버전별 경로를 보관 — 비율 변경이 코드 재배포 없이 반영되는 지점
- **CloudFront Functions**(js-2.0, LIVE): viewer-request가 쿠키/무작위로 버전을 배정해 URI 재작성, viewer-response가 첫 배정에만 `x-sp-ab` 쿠키 발급
- **Distribution**: redirect-to-https, 커스텀 캐시 정책(쿠키 `x-sp-ab` 캐시 키 포함, TTL 0/300/3600) + 커스텀 Security Header 정책

## 모듈 3 — EKS Scaling 한눈에

SkillsMarket 주문 처리의 큐 기반 오토스케일링. Terraform + eksctl + helm + kubectl 순서로 쌓는다.

- **SQS**: 주문 큐 `skm-order-queue` — KEDA 스케일링의 트리거이자 지급 앱(Consumer)의 입력
- **EKS**: `skm-eks-cluster` 1.35. Addon NodeGroup(t3.medium 1대 고정)은 `CriticalAddonsOnly` taint로 시스템 컴포넌트 전용
- **App**: 지급 Flask SQS Consumer를 CloudShell에서 빌드해 ECR로, `order-processor` Deployment(1 replica, 500m/512Mi)는 Karpenter 노드에서만 구동
- **KEDA**(ns `keda`): 메시지 5건당 Pod 1개, 1~5 replica — 큐가 비면 1개로 축소
- **Karpenter**(kube-system): Pending Pod 감지 시 t3.small/medium 노드 자동 증설, 유휴 60초 후 반환
