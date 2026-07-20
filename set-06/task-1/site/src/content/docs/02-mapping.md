---
title: "요구사항·채점 매핑"
sidebar:
  order: 2
---

| 채점 | 배점 | 구현 위치 | 핵심 판정 기준 |
|---|---|---|---|
| 1-1 VPC | 1.0 | `terraform/vpc.tf` | CIDR 10.0.0.0/16, 서브넷 **정확히 2개**(a=10.0.10.0/24, b=10.0.11.0/24) |
| 1-2 Route Table | 1.0 | `terraform/vpc.tf` | private-rtb-a/b의 `Routes[].DestinationCidrBlock`이 `10.0.0.0/16` 하나만(Gateway Endpoint 라우트는 이 필드가 없어 무관, §0-2) |
| 1-3 NAT Gateway | 1.0 | `terraform/vpc.tf` | 계정 내 NAT **0개**, IGW는 `gj2026-igw` 1개 |
| 2-1 ECR Repository | 1.0 | `terraform/ecr.tf` | repository name `book` |
| 2-2 ECR Image Size | 1.5 | `app/Dockerfile` + 런북 | `latest` 태그 이미지 `imageSizeInBytes` ≤ 3MB → **zstd 압축 필수** |
| 3-1 DynamoDB Config | 1.0 | `terraform/dynamodb.tf` | PK `booking_id`, GSI `client_id-index`(PK `client_id`) |
| 3-2 DynamoDB Encryption | 0.5 | `terraform/kms.tf` | SSE CMK가 `alias/gj2026-db-key` |
| 3-3 Access Restrictions | 1.0 | `terraform/dynamodb.tf` | 관리자 CloudShell `put-item`도 `AccessDeniedException` |
| 4-1 EKS Config | 1.0 | `eksctl/cluster.yaml` | 1.35 / ACTIVE / **public·private 엔드포인트 둘 다 True** / secret 암호화 CMK |
| 4-2 NodeGroup Config | 1.5 | `eksctl/cluster.yaml` | `BOTTLEROCKET_x86_64`, t3.medium×2 / m5.large×2 |
| 4-3 Node Naming | 1.5 | `eksctl/cluster.yaml` (bootstrap container) | 노드명 `gj2026.<instance_id>.(addon\|app).node` |
| 4-4 Application Pods | 1.0 | `k8s/app/` | `kubectl get deploy -n skills book` → 2/2 |
| 4-5 Network Policy | 1.5 | `k8s/app/securitygrouppolicy.yaml` + `terraform/vpc.tf`(Pod SG) | skills ns의 임의 Pod → `book-svc:8080` **타임아웃**, ALB는 정상 |
| 5-1 ALB Config | 1.0 | `terraform/alb.tf` | scheme `internal`, VPC = `gj2026-vpc` |
| 6-1 S3 Object | 1.0 | `terraform/s3.tf` | 루트에 `index.html`, `main.jpeg` (하위 디렉토리 금지) |
| 6-2 S3 Encryption | 1.0 | `terraform/s3.tf` | 기본 암호화 KMS = `alias/gj2026-s3-key` |
| 7-1 Lambda Config | 1.0 | `terraform/lambda.tf` | `gj2026-book-reservation` / `python3.14` / Active |
| 8-1 S3 Static Content | 1.0 | `terraform/cloudfront.tf` + Function | `/` Miss, `/main.jpeg` Miss, `/index.html` **Hit** |
| 8-2 ALB API | 1.5 | 전체 통합 | CF 경유 POST → `{"booking_id":"..."}` |
| 8-3 Lambda API 1 | 1.5 | `terraform/lambda.tf`(Function URL) + `lambda/index.py` | 전체 조회 JSON 배열 |
| 8-4 Lambda API 2 | 1.5 | 위와 동일 | `?client_id=C001` GSI 조회 |
| 9-1 HTTP Method | 1.5 | `terraform/waf.tf`(CLOUDFRONT scope) | `/v1/book` GET → `Method Not Allowed` + 405 |
| 9-2 Query String | 1.5 | `terraform/waf.tf`(CLOUDFRONT scope) | 잘못된 `client_id` → `Access Denied` + 403 |
| 10-1 Fluent Bit | 1.5 | `k8s/logging/` | AZ별 로그 스트림 2개, 메시지가 **JSON**이고 `remote_addr` 필드 존재 |
| 10-2 Grafana | 1.5 | `k8s/monitoring/` | `WSI Dashboard` / `Query Count Panel`에 `ALL`·`C001` 시리즈 |
