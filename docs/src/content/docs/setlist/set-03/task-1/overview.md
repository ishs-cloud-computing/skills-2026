---
title: 1과제 개요
description: 3세트 1과제 — EKS 기반 콘서트 예약(Book) 플랫폼 설계 개요
sidebar:
  order: 1
---

EKS 기반 콘서트 예약(Book) 플랫폼 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 배포한다.

> **문서 유형** — 실행은 **[배포 런북](../runbook/)**(how-to)을 위→아래로 따라간다. 각 단계의 이유는
> **[설계 근거](../deployment/)**(explanation), 채점 항목 대조는 **[요구사항 ↔ 구현 매핑](../mapping/)**
> (reference)에 있다. 저장소의 `README.md`(PowerShell 7) / `README.linux.md`(Linux)와 동일한 런북이다.

모든 리소스는 서울(`ap-northeast-2`) 리전 기준(단, WAF 는 scope=CLOUDFRONT 라 `us-east-1`).
`terraform`·`eksctl` 은 **본 PC(PowerShell 7)**, 컨테이너 빌드는 **일반 CloudShell**,
kubectl/helm 작업과 채점은 **CloudShell VPC environment(`mark-sg`)** 에서 한다.

## 구성 한눈에

- **네트워크/AWS 인프라** (`terraform/`): VPC, KMS×5, DynamoDB, ECR, S3, Lambda, CloudFront, WAF, IAM.
- **클러스터** (`eksctl/cluster.yaml`): EKS 1.35 fully private, authMode=API, Pod Identity, NG 2개(addon/workload).
- **K8s 리소스** (`k8s/`): CoreDNS 내부 도메인 패치, 앱(Deployment/Service/PDB/Ingress), 로깅(Fluent Bit),
  관측성(kube-prometheus-stack + PrometheusRule + 대시보드).

## 이 문서의 구성

- **[배포 런북](../runbook/)** — 위→아래로 실행하는 순수 명령(step 0~9). PowerShell 7 기준.
- **[설계 근거](../deployment/)** — 본 PC/CloudShell 2분할, terraform 2회 apply,
  fully-private 클러스터를 eksctl 로 생성하는 이유 등 설계 결정의 근거.
- **[요구사항 ↔ 구현 매핑](../mapping/)** — 채점 스크립트(mark.sh) 항목별 구현 위치.
- **[주의 · 알려진 한계](../notes/)** — 30% 변동 대응, 채점 스크립트 오타, 실발화 불가 알람 등 함정.
