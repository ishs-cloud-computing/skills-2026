---
title: 2과제 개요
description: 7세트 2과제 — Small Challenge, 독립 모듈 4개(NoSQL/CDN/EKS Scaling/Container Logging)
sidebar:
  order: 1
---

독립 모듈 4개를 Terraform / eksctl / Kubernetes manifest 로 배포한다. 각 모듈은 리전이 다르고 서로 간섭하지 않는다.

> **문서 유형** — 실행은 저장소의 모듈별 `README.md`(how-to)를 위→아래로 따라간다.
> 설계 결정의 이유는 **[설계 근거](../deployment/)**, 채점 항목 대조는
> **[요구사항 ↔ 구현 매핑](../mapping/)**, 함정은 **[주의 · 알려진 한계](../notes/)** 에 있다.

## 모듈 구성

| 모듈 | 주제 | 리전 | 핵심 서비스 | 배점 |
|------|------|------|-------------|------|
| 1 | NoSQL 예약 시스템 | ap-southeast-1 | DynamoDB(Stream/GSI/PITR), Lambda, EC2 | 7.5 |
| 2 | CDN A/B 테스팅 | us-east-1 | CloudFront Functions, KVS, OAC, S3 | 7.5 |
| 3 | EKS 스케일링 | ap-northeast-2 | SQS, EKS 1.35, KEDA, Karpenter | 7.5 |
| 4 | 컨테이너 로깅 | ap-northeast-1 | EKS 1.35, OTel Collector, Loki, Grafana, ALB | 7.5 |

## 머신 분할

- **본 PC (PowerShell 7)**: 모듈별 `terraform apply`. 모듈 3 은 `eksctl`·helm·kubectl 도 본 PC 에서 한다(장시간 `eksctl create` 를 CloudShell 유휴 회수에서 보호). Linux 면 각 모듈의 `README.linux.md`.
- **CloudShell (모듈별 리전)**: docker 이미지 빌드(대회 PC 에 Docker 없음)와 `mark/markN.sh` 셀프 채점. 모듈 4 는 `eksctl`·helm·kubectl 도 CloudShell 에서 한다.

## 사용 버전 (작성 시점 최신 안정, 고정)

| 구성요소 | 버전 |
|----------|------|
| terraform aws provider | ~> 6.52 |
| KEDA 차트 | 2.20.1 |
| Karpenter 차트 | 1.14.0 |
| AWS Load Balancer Controller 차트 | 3.4.2 |
| Loki 차트 (grafana-community) | 18.5.1 (Loki 3.7.x) |
| Grafana 차트 | 10.5.15 |
| otel/opentelemetry-collector-contrib | 0.156.0 |
| kubectl | v1.35.6 |
| flask (모듈 4 이미지) | 3.1.3 |
