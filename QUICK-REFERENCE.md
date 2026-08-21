# QUICK REFERENCE

가장 자주 나오는 문제지 표현만 빠르게 찾는다. 전체 기준표는 [KIT-INDEX.md](KIT-INDEX.md)다.

| 문제지에서 찾을 말 | Basic KIT | 열 파일 |
| --- | --- | --- |
| MSK · Kafka · Streaming | MSK hardening | [msk-hardening](shared/addons/msk-hardening/README.md) |
| VPC Lattice · Service Network · Cross-VPC | Lattice hardening | [lattice-hardening](shared/addons/lattice-hardening/README.md) |
| Karpenter · Node Scaling | EKS scaling variants | [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md) |
| CloudFront · CDN | CloudFront hardening | [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md) |
| EventBridge · Security Event | EventBridge security rules | [eventbridge-security-rules](shared/addons/eventbridge-security-rules/README.md) |
| Container Logging · Grafana · Loki | Observability | [observability](shared/addons/observability/README.md) |
| WAF | WAF extra rules | [waf-extra-rules](shared/addons/waf-extra-rules/README.md) |
| RDS | RDS connection | [rds-connection](shared/addons/rds-connection/README.md) |
| VPN | Client VPN | [client-vpn](shared/addons/client-vpn/README.md) |
| NoSQL | NoSQL hardening | [dynamodb-hardening](shared/addons/dynamodb-hardening/README.md) |
| DocumentDB | DocumentDB hardening | [docdb-hardening](shared/addons/docdb-hardening/README.md) |
| Lambda · REST API | Lambda GET API | [lambda-get-api](shared/addons/lambda-get-api/README.md) |

열 파일을 정했으면 해당 세트의 공식 과제·채점 문서를 먼저 확인하고, 계정·리전을 확인한 뒤 `init → validate → plan → apply` 순으로 진행한다. 기능 확인(VERIFY) 후에만 공식 채점(SCORE)을 한다.
