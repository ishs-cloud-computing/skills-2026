---
title: "설계 개요"
sidebar:
  order: 0
---

EKS(Bottlerocket) 위에 Book API를 배포하고, CloudFront 단일 엔드포인트로 S3 정적 페이지 · ALB API · Lambda 조회 API · Grafana를 함께 서비스하는 과제. 전 리소스 `ap-northeast-2`(WAF Web ACL만 AWS 제약상 예외, §3.10). **NAT 없음 / Private Subnet 2개뿐**이라는 제약이 설계 전반을 지배한다.

## 아키텍처

```
사용자 ──> CloudFront (gj2026-cdn, HTTP→HTTPS redirect)
   │       └ WAF Web ACL(CLOUDFRONT scope) gj2026-waf-acl 연결 — 모든 behavior 공통
   │           ├─ Rule1 deny-non-post-on-api      : /v1/book* AND method≠POST      → 405 Block
   │           └─ Rule2 deny-invalid-client-id    : /reservation* AND client_id 정규식 불일치 → 403 Block
   │
   ├─ Behavior[Default]        ──> S3 Origin(OAC) gj2026-static-<비번호>            [캐싱 O]
   │                                ├ CloudFront Function(viewer-request): 확장자 없는 URI → /index.html
   │                                └ SSE-KMS alias/gj2026-s3-key ← OAC에 Decrypt/GenerateDataKey 허용
   │
   ├─ Behavior[/v1/book*]  ┐
   ├─ Behavior[/grafana*]  ┘ VPC Origin(gj2026-alb-origin) [캐싱 X, 쿼리스트링 전달]
   │                          └─> ALB gj2026-alb (internal, private subnet a/b)
   │                                ├─ TG gj2026-book-tg(8080)    → EKS book Pod x2 (ns: skills)
   │                                │     ServiceAccount book-sa ─IRSA→ Role gj2026-book-app-role
   │                                │     (dynamodb:PutItem, kms:Decrypt → db-key)
   │                                └─ TG gj2026-grafana-tg(3000) → Grafana Pod (ns: monitoring)
   │                                      ServiceAccount ─IRSA→ Role gj2026-grafana-role
   │                                      (cloudwatch:GetMetricData/ListMetrics)
   │
   └─ Behavior[/reservation*]  ──> Lambda Function URL(OAC, AWS_IAM) gj2026-book-reservation
                                     IAM Role gj2026-lambda-role
                                     (dynamodb:Scan/Query, kms:Decrypt → db-key)

DynamoDB books (SSE-KMS alias/gj2026-db-key, GSI client_id-index)
   ← book-app-role : PutItem (IRSA, Gateway Endpoint 경유)
   ← lambda-role    : Scan/Query (VPC 밖, 퍼블릭 엔드포인트)
   ← 그 외 모든 주체: 리소스 기반 정책으로 쓰기 Deny (채점 3-3)

ECR(Private)
   ├─ book                      ← EKS app 노드 pull  (book Pod 이미지, zstd 압축)
   └─ ecr-public/nginx/nginx    ← EKS addon 노드 pull (pull-through cache, nginx-test Pod)

EKS Cluster gj2026-eks-cluster  — Secret 봉투 암호화 CMK alias/gj2026-eks-key

로그/메트릭 흐름
   book Pod(ns: skills) access log
     └─ Fluent Bit DaemonSet(ns: logging) ─IRSA→ Role gj2026-fluentbit-role(logs:PutLogEvents)
          └─ CloudWatch Logs /eks/book-svc/access (remote_addr 대역별 스트림 분리: -2a · -2b)
   Lambda gj2026-book-reservation
     └─ EMF 커스텀 메트릭(namespace gj2026/reservation, dim client_id) → CloudWatch Metrics
          └─ Grafana(ns: monitoring, 위 gj2026-grafana-role로 조회)
               └─ "WSI Dashboard" > Query Count Panel (ALL / C001 시리즈)
```

## 문서 안내

- **런북**: [PowerShell (기본)](runbook/powershell/) · [Linux / bash](runbook/linux/) — 위에서 아래로 그대로 실행
- **설계**: 재검토 기록 → 요구사항·채점 매핑 → 도메인별 설계 → 함정 26개 → 검증 시드
