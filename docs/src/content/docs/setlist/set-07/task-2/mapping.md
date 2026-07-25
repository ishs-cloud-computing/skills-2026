---
title: 요구사항 ↔ 구현 매핑
description: 채점 스크립트(mark1~4.sh) 항목별 구현 위치
sidebar:
  order: 4
---

채점 스크립트 `mark/markN.sh` 의 각 항목을 어느 파일이 커버하는지 대조표.
경로는 `set-07/task-2/` 기준. "실배포 검증" = 코드 검토만으로는 확정 불가, 배포 후 확인 필요.

## 모듈 1 — NoSQL (mark1.sh)

| mark | 검사 항목 | 구현 |
|------|----------|------|
| 1-1 | 테이블 이름/키/속성/Stream/PPR + PITR | `module-1-nosql/terraform/dynamodb.tf` |
| 1-2 | GSI 이름/키/Projection + 감사 테이블 | `dynamodb.tf` |
| 1-3 | Lambda 이름/python3.13/30s + ESM Enabled | `lambda.tf` |
| 1-4 | EC2 태그 조회 + `:8080/healthcheck` 200 | `ec2.tf`, `ec2-userdata.sh.tftpl` (실배포 검증: userdata 완료) |
| 1-5 | reserve/reserve/cancel/cancel 정확 응답 | 제공 `app.py` + `dynamodb.tf` GSI 키 일치 (실배포 검증) |
| 1-6 | GSI 조회 + 30초 내 감사 2건 적재 | `lambda.tf` ESM 기본 배칭 + 제공 `lambda.py` (실배포 검증) |

## 모듈 2 — CDN Function (mark2.sh)

| mark | 검사 항목 | 구현 |
|------|----------|------|
| 2-1 | 버킷 이름/오브젝트 2개/Public 차단 4종/정책 Statement[0] | `module-2-cdn-function/terraform/s3.tf` |
| 2-2 | KVS 3키 정확값 + 함수 2개 DEPLOYED/js-2.0/KVS 연결 | `kvs.tf`, `functions.tf` |
| 2-3 | 캐시 정책 whitelist/TTL + redirect-to-https + OAC + 함수 연결 | `policies.tf`, `cloudfront.tf` |
| 2-4 | 쿠키 강제 시 본문 일치 + Set-Cookie 없음 + HTTP→HTTPS | `func/ab-request.js`, `func/ab-response.js` (실배포 검증) |
| 2-5 | 무작위 배정 + Max-Age/Path + 쿠키 보존 | `func/*.js` (실배포 검증) |
| 2-6 | weight 1.0/0.0 반영 + 0.3 복원 | `func/ab-request.js` 매 호출 `kvs.get` (실배포 검증) |

## 모듈 3 — EKS Scaling (mark3.sh)

| mark | 검사 항목 | 구현 |
|------|----------|------|
| 3-1 | 큐 URL | `module-3-eks-scaling/terraform/sqs.tf` |
| 3-2 | 클러스터 1.35 ACTIVE + NG t3.medium 1/1/1 + 노드 Name 태그 | `eksctl/cluster.yaml` (`instanceName`) |
| 3-3 | Pod 의 노드 nodepool 라벨 + replicas/port/requests + env 3종 | `k8s/20-deployment.yaml` |
| 3-4 | keda-operator Pod(keda ns) + order-scaler 1/5/aws-sqs-queue/5 | README 4) helm + `k8s/30-keda-scaledobject.yaml` |
| 3-5 | karpenter Pod(kube-system) + consolidation/타입/taint/NodeClass | README 5) helm + `k8s/10-karpenter-nodepool.yaml` |
| 3-6 | 100건 주입 → Ready Pod ≥5, App 노드 ≥2 | `20`+`10` 리소스 계산 (실배포 검증) |
| 3-7 | purge → Pod 1, 노드 1 | `30` scaleDown 30s + `10` consolidate 60s (실배포 검증) |

## 모듈 4 — Container Logging (mark4.sh)

| mark | 검사 항목 | 구현 |
|------|----------|------|
| 4-1 | 클러스터 1.35 + NG t3.medium 2/2/2 + zone 2종 | `module-4-container-logging/eksctl/cluster.yaml` |
| 4-2 | ALB 2대 active/application/internet-facing + TG 전 타깃 healthy | `terraform/alb.tf` + `k8s/app/12-`,`k8s/monitoring/30-*targetgroupbinding.yaml` (실배포 검증) |
| 4-3 | log-generator 2 / ds o11y-otel / svc o11y-loki ClusterIP 3100 / o11y-grafana 1 | `k8s/app/10-`, `k8s/logging/22-`, `loki-values.yaml`(fullnameOverride), `grafana-values.yaml`(fullnameOverride) |
| 4-4 | `/healthz` → `{"status":"ok"}`, `/log` → error/3 | 제공 `app.py` + `app/Dockerfile` (실배포 검증) |
| 4-5 | LogQL `{k8s_namespace_name="o11y"} \| json \| level="ERROR"` 3분 내 로그 | `k8s/logging/21-otel-configmap.yaml` + `loki-values.yaml` OTLP (실배포 검증) |
| 4-6 | Grafana 로그인/3패널/범례 plain/Datasource Save&Test | `grafana-values.yaml` + `k8s/monitoring/dashboard.json` (실배포 검증, 수동) |
