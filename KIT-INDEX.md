# KIT INDEX

문제지의 표현을 가장 먼저 열어 볼 KIT으로 연결한다. 경로의 모든 KIT은 `shared/addons/`에서 필요한 파일을 **복사·부착**하는 방식이다. 기존 세트 구현을 고칠 필요가 없으면 먼저 해당 KIT의 README를 따른다.

## 문제지 표현 → KIT

| Keyword / phrase | Basic KIT | Mode | Path |
| --- | --- | --- | --- |
| NoSQL · DynamoDB | NoSQL hardening | COPY | [dynamodb-hardening](shared/addons/dynamodb-hardening/README.md) |
| DocumentDB | DocumentDB hardening | COPY | [docdb-hardening](shared/addons/docdb-hardening/README.md) |
| CloudFront · CDN · Distribution | CloudFront hardening | COPY | [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md) |
| CloudTrail · Audit trail · Event history | CloudTrail hardening | COPY | [cloudtrail-hardening](shared/addons/cloudtrail-hardening/README.md) |

| EKS Node Scaling · Karpenter · NodePool | EKS scaling variants | COPY | [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md) |
| VPC Lattice · Service Network · Cross-VPC Service | Lattice hardening | COPY | [lattice-hardening](shared/addons/lattice-hardening/README.md) |
| EventBridge · Security Event | EventBridge security rules | COPY | [eventbridge-security-rules](shared/addons/eventbridge-security-rules/README.md) |
| Step Functions · State Machine · Workflow | Step Functions hardening | COPY | [sfn-hardening](shared/addons/sfn-hardening/README.md) |

| Client VPN · VPN | Client VPN | COPY | [client-vpn](shared/addons/client-vpn/README.md) |
| RDS · RDS Proxy · Database connection | RDS connection | COPY | [rds-connection](shared/addons/rds-connection/README.md) |
| MSK · Kafka · Streaming | MSK hardening | COPY | [msk-hardening](shared/addons/msk-hardening/README.md) |
| Container Logging · Grafana · Loki | Observability | COPY | [observability](shared/addons/observability/README.md) |
| CloudWatch Alarm | CloudWatch alarms | COPY | [cw-alarms](shared/addons/cw-alarms/README.md) |
| CloudWatch Dashboard | CloudWatch dashboard | COPY | [cw-dashboard](shared/addons/cw-dashboard/README.md) |
| Logs Insights · Log query | CloudWatch Logs Insights | COPY | [cw-logs-insights](shared/addons/cw-logs-insights/README.md) |
| WAF · Web ACL | WAF extra rules | COPY | [waf-extra-rules](shared/addons/waf-extra-rules/README.md) |
| Lambda · Function URL | Lambda hardening | COPY | [lambda-hardening](shared/addons/lambda-hardening/README.md) |
| REST API · API Gateway · Lambda GET API | Lambda GET API | COPY | [lambda-get-api](shared/addons/lambda-get-api/README.md) |
| VPC Endpoint · PrivateLink | VPC endpoints | COPY | [vpc-endpoints](shared/addons/vpc-endpoints/README.md) |
| VPC Flow Log | VPC flow log | COPY | [vpc-flow-log](shared/addons/vpc-flow-log/README.md) |
| ALB · Auto Scaling Group · EC2 Scaling | EC2 ASG + ALB | COPY | [ec2-asg-alb](shared/addons/ec2-asg-alb/README.md) |
| S3 hardening · Object Lock | S3 hardening | COPY | [s3-hardening](shared/addons/s3-hardening/README.md) |
| Secrets Manager · Secret rotation | Secrets Manager | COPY | [secrets-manager](shared/addons/secrets-manager/README.md) |
| SQS · DLQ | SQS hardening | COPY | [sqs-hardening](shared/addons/sqs-hardening/README.md) |
| Kinesis · Firehose | Kinesis / Firehose | COPY | [kinesis-firehose](shared/addons/kinesis-firehose/README.md) |
| IAM audit role · Cross-account audit | IAM audit role | COPY | [iam-audit-role](shared/addons/iam-audit-role/README.md) |
| Keycloak · OIDC | Keycloak | COPY | [keycloak](shared/addons/keycloak/README.md) |

## 실행 전 공통 규칙

1. 해당 세트의 `task.md`, `mark.md`, `mark*.sh`, `NOTES.md`를 먼저 읽는다. 공식 지급물(`provided/`, `task.md`, `mark.md`, `mark*.sh`)은 수정하지 않는다.
2. README의 대상 Terraform 디렉터리로 이동한 뒤 `aws sts get-caller-identity`와 `aws configure get region`으로 지급 계정과 과제지 리전을 확인한다.
3. `terraform init` → `terraform validate` → `terraform plan`으로 기존 리소스의 의도치 않은 diff가 없는 것을 확인한 뒤에만 apply한다. `terraform init -upgrade`는 사용하지 않는다.
4. **VERIFY**는 KIT README의 기능 확인, **SCORE**는 해당 세트의 공식 `mark.md`와 `mark*.sh` 절차다. 둘을 서로 대신하지 않는다.

공통 실패 대응은 [shared/TROUBLESHOOTING-COMMON.md](shared/TROUBLESHOOTING-COMMON.md)를 참조한다. 자주 쓰는 항목만 [QUICK-REFERENCE.md](QUICK-REFERENCE.md)에 있다.
