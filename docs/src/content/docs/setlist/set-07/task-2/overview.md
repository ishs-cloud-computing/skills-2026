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
| 2 | CDN Function | us-east-1 | S3 + CloudFront Functions + KVS | 미착수 |
| 3 | EKS Scaling | ap-northeast-2 | EKS + KEDA(SQS) + Karpenter | 미착수 |
| 4 | Container Logging | ap-northeast-1 | EKS + OTel + Loki + Grafana | 미착수 |

## 모듈 1 — NoSQL 한눈에

BigBae Trains 기차 티켓 예매 시스템. Terraform 단일 apply로 끝난다 (EKS 무관).

- **DynamoDB**: 예약 테이블(`train_id`/`seat_id`, Streams NEW_AND_OLD_IMAGES, PITR, sparse GSI `gsi-user-reservations`) + 감사 테이블(`event_id`)
- **Lambda**: Streams 트리거로 예약 변경을 감사 테이블에 적재 (`python3.13`, 지급 `lambda.py` 무수정)
- **EC2**: 지급 Flask 앱(`app.py`)을 systemd로 :8080 서빙, 조건부 쓰기(409)와 GSI 조회 API 제공
