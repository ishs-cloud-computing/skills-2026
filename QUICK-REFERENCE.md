# QUICK REFERENCE

가장 자주 나오는 문제지 표현만 추린 초고속 검색표다. 전체 기준표(authoritative source)는 [KIT-INDEX.md](KIT-INDEX.md)다.

| 문제지에서 찾을 말 | Basic KIT | 열 파일 |
| --- | --- | --- |
| MSK · Kafka · Streaming | MSK hardening | [msk-hardening](shared/addons/msk-hardening/README.md) |
| VPC Lattice · Service Network · Cross-VPC | Lattice hardening | [lattice-hardening](shared/addons/lattice-hardening/README.md) |
| Karpenter · EKS Node Scaling | EKS scaling variants | [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md) |
| CloudFront · CDN | CloudFront hardening | [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md) |
| EventBridge · Security Event | EventBridge security rules | [eventbridge-security-rules](shared/addons/eventbridge-security-rules/README.md) |
| Container Logging · Grafana · Loki | Observability | [observability](shared/addons/observability/README.md) |
| WAF · Web ACL 신규 생성 | WAF | [waf](shared/addons/waf/README.md) |
| WAF 룰 추가 · 관리형 룰 · Rate limit | WAF extra rules | [waf-extra-rules](shared/addons/waf-extra-rules/README.md) |
| KMS · CMK · 저장 데이터 암호화 | KMS | [kms](shared/addons/kms/README.md) |
| IRSA · ServiceAccount role-arn · Pod Identity | Security (IRSA) | [irsa](shared/addons/irsa/README.md) |
| RDS · RDS Proxy | RDS connection | [rds-connection](shared/addons/rds-connection/README.md) |
| VPN | Client VPN | [client-vpn](shared/addons/client-vpn/README.md) |
| NoSQL · DynamoDB | NoSQL hardening | [dynamodb-hardening](shared/addons/dynamodb-hardening/README.md) |
| DocumentDB | DocumentDB hardening | [docdb-hardening](shared/addons/docdb-hardening/README.md) |
| REST API · API Gateway 신규 구성 | Lambda GET API | [lambda-get-api](shared/addons/lambda-get-api/README.md) |
| CloudWatch Alarm | CloudWatch alarms | [cw-alarms](shared/addons/cw-alarms/README.md) |

여기에 없으면 [KIT-INDEX.md](KIT-INDEX.md)를 본다. 위 표는 `irsa`(부착 파일 없는 README 스니펫)를 빼면 전부 `terraform validate` 통과본이다 — 상태 정의는 [KIT-INDEX Status](KIT-INDEX.md#status-가-뜻하는-것).

열 파일을 정했으면 KIT README의 `RUN guard` 절을 따른다 — 공식 과제·채점 문서 확인 → 계정·리전 확인 → `init` → `validate` → `plan` → `apply`. 기능 확인(VERIFY) 후에만 공식 채점(SCORE)을 한다. 기본 RUN에 `destroy`를 넣지 않는다.
