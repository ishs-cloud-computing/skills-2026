---
title: 요구사항 ↔ 구현 매핑
description: 채점 스크립트(mark.sh) 항목별 구현 위치
sidebar:
  order: 4
---

채점 스크립트 `mark.sh` 의 각 항목을 어느 파일이 커버하는지 대조표.
"step N" 은 저장소 런북(`README.md`)의 단계 번호를 가리킨다.

| mark | 검사 항목 | 구현 |
|------|----------|------|
| 1-1/1-2 | VPC·서브넷 이름/CIDR, IGW/NAT/RTB 매핑 | `vpc.tf` (Reference01 그대로, 변수화) |
| 2-1 | PK client_id, GSI booking_id, PPR, SSE-KMS, 삭제방지, PITR 35일, 리소스 정책 2건, db-kms | `dynamodb.tf`, `kms.tf` |
| 3-1 | scanOnPush, MUTABLE_WITH_EXCLUSION+`v1*`, KMS, 태그 v1.0.0 단독 | `ecr.tf`, step 2 (latest 금지) |
| 4-1 | 1.35, private, 전체 로그, 클러스터 SG any-open 없음, CoreDNS 도메인, eks-kms | `eksctl/cluster.yaml`, `k8s/01-coredns-wsc2026.yaml` |
| 4-2 | NG 2개 이름/타입/라벨/노드 2대씩 | `eksctl/cluster.yaml` |
| 4-3 | 세 롤에 AdministratorAccess 없음 | eksctl 기본 최소 롤 |
| 5-1 | deploy 2/2, svc, ingress ALB DNS, PDB minAvailable 1 | `k8s/app/*` |
| 5-2 | replicas/nodeSelector/topologySpread/250m/512Mi | `k8s/app/02-deployment.yaml` |
| 5-3 | probe 3종 /health:8080, book-config 데이터 | `k8s/app/01-configmap.yaml`, `02-deployment.yaml` |
| 5-4 | 앱 파드가 application 노드에만 | nodeSelector + workload NG taint |
| 5-5 | Pod Identity SA/역할 정책 | `cluster.yaml` association + `iam.tf` **관리형** 정책 |
| 6-1 | 버킷명/퍼블릭차단4/SSE-KMS+BucketKey/static 객체별 KMS | `s3.tf` (`static/` 마커 포함) |
| 7-1 | python3.12, TABLE_NAME 암호문(AQICAH...), function-kms | `lambda.tf` (`aws_kms_ciphertext`) |
| 7-2 | 역할/정책 이름, Query 포함·Action 에 `*` 없음 | `iam.tf` (BasicExecutionRole 미부착, logs 액션 명시) |
| 8-1 | internet-facing, SG 이름 단독, 직접 curl 차단(000) | `k8s/app/05-ingress.yaml` + `security.tf`(CF prefix list) |
| 9-1 | CF 도메인 200 (루트 정적 페이지) | `cloudfront.tf` (origin_path=/static) |
| 9-2 | S3 CachingOptimized / ALB·Lambda CachingDisabled | `cloudfront.tf` (관리형 정책 ID) |
| 9-3 | POST /booking → GET /v1/book 필드순서+KST | CloudFront Function rewrite + `lambda/index.py` |
| 10-1 | WAF 이름, SQLi/XSS 403, rate Limit≤200 | `waf.tf` (커스텀 sqli/xss + rate 200/60s) |
| 11-1 | observability 에 fluent-bit/prometheus/grafana Running, Grafana LB | `k8s/logging/fluent-bit.yaml`, kps values |
| 11-2 | datasource 3개 이름·타입, 대시보드 wsc2026-grafana-dashboard | kps values, `dashboard.json` |
| 11-3 | 대시보드 Row 5종 + 로그 형식 | `dashboard.json`, fluent-bit `format.lua` |
| 11-4 | 알람 5종 Firing | `prometheus-rules.yaml` + log_to_metrics (HighLatency 실발화 불가 — `NOTES.md`) |
