---
title: "재검토 기록"
sidebar:
  order: 1
---

최초 설계 이후 `task.pdf`(다이어그램 이미지 포함)와 `mark.sh`를 다시 원본에서 읽고, 핵심 가정 2건을 실측·재검증해 아래와 같이 정정했다.

1. **Lambda는 ALB가 아니라 CloudFront에서 직접 연결한다.** 문제지 1페이지 다이어그램을 실제로 렌더링해 확인한 결과, `Lambda` 아이콘은 `VPC` 박스 **밖**에 있고 화살표가 `CloudFront`에서 **직접** 내려와 `Lambda`로 들어간다(ALB·WAF 박스를 거치지 않음). 텍스트 근거도 있다 — "9. Load Balancing"이 명명한 Target Group은 `gj2026-book-tg`, `gj2026-grafana-tg` **딱 2개뿐**이며, Lambda용 3번째 Target Group 이름이 어디에도 없다. 이 과제는 리소스명을 전부 명시적으로 지정하는 방식이라, 이름이 없다는 것 자체가 "그 리소스가 없다"는 뜻이다. 최초 설계는 "Web ACL 1개로 CloudFront와 ALB를 동시에 커버할 수 없다"는 이유로 ALB Lambda 타깃그룹을 채택했는데, 이는 **WAF를 ALB(REGIONAL)에 붙인다는 전제 자체가 틀렸던 것** — WAF를 **CloudFront(CLOUDFRONT scope)에** 붙이면 Web ACL 1개가 엣지에서 `/v1/book`·`/reservation` 두 경로를 모두 검사하고, 그 뒤에 ALB든 Lambda Function URL이든 원하는 오리진으로 라우팅할 수 있다. §3.7·3.8·3.9·3.10 전면 수정.
2. **Gateway Endpoint는 1-2 채점을 깨지 않는다 — 오히려 DynamoDB엔 그것뿐이다.** 최초 설계는 "Gateway Endpoint가 라우트 테이블에 prefix-list 라우트를 추가해 `Routes[].DestinationCidrBlock` 출력에 `None`이 섞인다"고 판단해 전부 Interface Endpoint로 우회했다(S3까지 포함). 실제로 `jmespath` 라이브러리로 그 정확한 쿼리를 재현해보면, Gateway Endpoint 라우트는 `DestinationCidrBlock` 키 자체가 없고(`DestinationPrefixListId`만 있음) — JMESPath 프로젝션은 **결과가 null인 원소를 배열에서 아예 제외**하므로 `Routes[].DestinationCidrBlock`은 로컬 라우트 `10.0.0.0/16` 하나만 반환한다(실측: `jmespath.search(...)` → `['10.0.0.0/16']`, `None` 없음). 즉 Gateway Endpoint를 추가해도 1-2 출력은 그대로 정확히 일치한다. 이건 단순 최적화가 아니라 **필수 정정**이다 — DynamoDB는 애초에 Interface Endpoint 자체가 존재하지 않는 서비스(Gateway 전용)라, 이전 설계의 "dynamodb(interface)"는 AWS에 존재하지 않는 리소스를 만들려 한 것이었다. §3.1 전면 수정.

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
