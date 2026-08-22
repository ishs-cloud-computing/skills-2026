# KIT INDEX

문제지의 표현을 가장 먼저 열어 볼 KIT 하나로 연결하는 역색인이다. 모든 KIT은 `shared/addons/`의 파일을 대상 세트로 **복사·부착(COPY)**하는 방식이며, addon 디렉터리 자체는 독립 `apply` 대상이 아니다 — 기존 세트의 Terraform state를 건드리지 않는다.

자주 쓰는 표현만 추린 것은 [QUICK-REFERENCE.md](QUICK-REFERENCE.md)이고, 이 문서가 authoritative source다.

## Status 가 뜻하는 것

2026-08-22 저장소에서 실제로 돌린 결과다. **셋 다 "AWS 에 apply 해봤다"는 뜻이 아니다** — 당일 `plan` 은 반드시 직접 읽는다.

| Status | 근거 | 개수 |
| --- | --- | --- |
| `VALIDATED` | 프로바이더 스텁만 얹고 `terraform init` + `terraform validate` 통과. 선언되지 않은 변수 0개 | 33 |
| `LINTED` | Terraform 파일이 없는 k8s/자산 KIT. YAML·JSON 파싱 통과 | 2 |
| `DOC-ONLY` | 부착 파일 없이 README 스니펫만 있는 KIT. 문법 검증 대상이 아니다 | 1 |

## 문제지 표현 → KIT

### 컴퓨트 · EKS

| Keyword / phrase | Basic KIT | Status | Path |
| --- | --- | --- | --- |
| EKS Node Scaling · Karpenter · NodePool · 노드 자동 확장 | EKS scaling variants | `VALIDATED` | [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md) |
| EKS Control Plane 로깅 · Secret 암호화 · 노드 강화 · IMDS 차단 | EKS logging variants | `VALIDATED` | [eks-logging-variants](shared/addons/eks-logging-variants/README.md) |
| IRSA · ServiceAccount role-arn · Pod Identity · OIDC provider | Security (IRSA) | `DOC-ONLY` | [irsa](shared/addons/irsa/README.md) |
| ALB · Auto Scaling Group · EC2 Scaling | EC2 ASG + ALB | `VALIDATED` | [ec2-asg-alb](shared/addons/ec2-asg-alb/README.md) |
| ALB 액세스 로그 · 리스너 규칙 · 삭제 보호 | ALB hardening | `VALIDATED` | [alb-hardening](shared/addons/alb-hardening/README.md) |

### 네트워크

| Keyword / phrase | Basic KIT | Status | Path |
| --- | --- | --- | --- |
| VPC Lattice · Service Network · Cross-VPC Service | Lattice hardening | `VALIDATED` | [lattice-hardening](shared/addons/lattice-hardening/README.md) |
| VPC Endpoint · PrivateLink | VPC endpoints | `VALIDATED` | [vpc-endpoints](shared/addons/vpc-endpoints/README.md) |
| VPC Flow Log | VPC flow log | `VALIDATED` | [vpc-flow-log](shared/addons/vpc-flow-log/README.md) |
| Client VPN · VPN | Client VPN | `VALIDATED` | [client-vpn](shared/addons/client-vpn/README.md) |
| CloudFront · CDN · Distribution | CloudFront hardening | `VALIDATED` | [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md) |

### 데이터 · 스토리지

| Keyword / phrase | Basic KIT | Status | Path |
| --- | --- | --- | --- |
| NoSQL · DynamoDB | NoSQL hardening | `VALIDATED` | [dynamodb-hardening](shared/addons/dynamodb-hardening/README.md) |
| DocumentDB | DocumentDB hardening | `VALIDATED` | [docdb-hardening](shared/addons/docdb-hardening/README.md) |
| RDS · RDS Proxy · Database connection | RDS connection | `VALIDATED` | [rds-connection](shared/addons/rds-connection/README.md) |
| MSK · Kafka · Streaming · Message Broker | MSK hardening | `VALIDATED` | [msk-hardening](shared/addons/msk-hardening/README.md) |
| Kinesis · Firehose · 실시간 전송 | Kinesis / Firehose | `VALIDATED` | [kinesis-firehose](shared/addons/kinesis-firehose/README.md) |
| SQS · DLQ · 메시지 큐 | SQS hardening | `VALIDATED` | [sqs-hardening](shared/addons/sqs-hardening/README.md) |
| S3 hardening · Object Lock · 버킷 정책 | S3 hardening | `VALIDATED` | [s3-hardening](shared/addons/s3-hardening/README.md) |

### 애플리케이션 · 서버리스

| Keyword / phrase | Basic KIT | Status | Path |
| --- | --- | --- | --- |
| REST API · API Gateway 신규 구성 · Lambda GET API | Lambda GET API | `VALIDATED` | [lambda-get-api](shared/addons/lambda-get-api/README.md) |
| API Gateway 액세스 로그 · 스로틀 · X-Ray · Usage Plan | API Gateway hardening | `VALIDATED` | [apigw-hardening](shared/addons/apigw-hardening/README.md) |
| Lambda 동시성 · Function URL · Lambda 보안 강화 | Lambda hardening | `VALIDATED` | [lambda-hardening](shared/addons/lambda-hardening/README.md) |
| VPC 내 Lambda → RDS 조회 · 신규 Lambda 개발 (task-3) | Lambda VPC + RDS | `VALIDATED` | [lambda-vpc-rds](shared/addons/lambda-vpc-rds/README.md) |
| Step Functions · State Machine · Workflow | Step Functions hardening | `VALIDATED` | [sfn-hardening](shared/addons/sfn-hardening/README.md) |
| EventBridge · Security Event · GuardDuty 이벤트 | EventBridge security rules | `VALIDATED` | [eventbridge-security-rules](shared/addons/eventbridge-security-rules/README.md) |

### 보안 · IAM

| Keyword / phrase | Basic KIT | Status | Path |
| --- | --- | --- | --- |
| WAF · Web ACL **신규 생성** | WAF | `VALIDATED` | [waf](shared/addons/waf/README.md) |
| WAF **룰 추가** · 관리형 룰 그룹 · Rate limit · Geo 차단 | WAF extra rules | `VALIDATED` | [waf-extra-rules](shared/addons/waf-extra-rules/README.md) |
| KMS · CMK · 저장 데이터 암호화 | KMS | `VALIDATED` | [kms](shared/addons/kms/README.md) |
| Secrets Manager · Secret rotation | Secrets Manager | `VALIDATED` | [secrets-manager](shared/addons/secrets-manager/README.md) |
| CloudTrail · Audit trail · Event history | CloudTrail hardening | `VALIDATED` | [cloudtrail-hardening](shared/addons/cloudtrail-hardening/README.md) |
| IAM audit role · Cross-account audit | IAM audit role | `VALIDATED` | [iam-audit-role](shared/addons/iam-audit-role/README.md) |
| ECR · 이미지 스캔 · 태그 불변성 · lifecycle policy | ECR hardening | `VALIDATED` | [ecr-hardening](shared/addons/ecr-hardening/README.md) |
| Keycloak · OIDC IdP · 외부 인증 | Keycloak | `VALIDATED` | [keycloak](shared/addons/keycloak/README.md) |

### 관측성

| Keyword / phrase | Basic KIT | Status | Path |
| --- | --- | --- | --- |
| Container Logging · Fluent Bit · Container Insights · 모니터링 도구 설치 | Observability | `LINTED` | [observability](shared/addons/observability/README.md) |
| Grafana · Loki · Prometheus | Observability | `LINTED` | [observability](shared/addons/observability/README.md) |
| Grafana 패널 · Prometheus Alert Rule (자산 묶음) | Grafana panels | `LINTED` | [grafana-panels](shared/addons/grafana-panels/README.md) |
| CloudWatch Alarm | CloudWatch alarms | `VALIDATED` | [cw-alarms](shared/addons/cw-alarms/README.md) |
| CloudWatch Dashboard | CloudWatch dashboard | `VALIDATED` | [cw-dashboard](shared/addons/cw-dashboard/README.md) |
| Logs Insights · Log query | CloudWatch Logs Insights | `VALIDATED` | [cw-logs-insights](shared/addons/cw-logs-insights/README.md) |

## 헷갈리는 표현

| 문제지 표현 | 판단 기준 | KIT |
| --- | --- | --- |
| WAF | Web ACL 자체가 없다 → `waf` · 이미 있고 룰만 추가 → `waf-extra-rules` | [waf](shared/addons/waf/README.md) · [waf-extra-rules](shared/addons/waf-extra-rules/README.md) |
| 로깅 | 컨테이너/애플리케이션 로그 → `observability` · EKS Control Plane 로그 → `eks-logging-variants` · VPC 트래픽 → `vpc-flow-log` | [observability](shared/addons/observability/README.md) |
| 스케일링 | EKS 노드 → `eks-scaling-variants` · EC2/ASG → `ec2-asg-alb` (1과제에 인프라 스케일링 문항은 출제되지 않는다) | [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md) |
| Lambda | REST API 뒤에 새로 만든다 → `lambda-get-api` · 기존 함수 강화(동시성·Function URL) → `lambda-hardening` · VPC 안에서 RDS 조회(task-3) → `lambda-vpc-rds` | [lambda-get-api](shared/addons/lambda-get-api/README.md) |
| OIDC | EKS Pod에 IAM 권한 → `irsa` · 외부 인증 IdP 구축 → `keycloak` | [irsa](shared/addons/irsa/README.md) |
| Grafana | 스택을 새로 세운다 → `observability` (경로 B) · 이미 있는 스택에 패널/알림 룰만 얹는다 → `grafana-panels` | [observability](shared/addons/observability/README.md) |

## 실행 전 공통 규칙

1. 해당 세트의 `task.md`, `mark.md`, `mark*.sh`, `NOTES.md`를 먼저 읽는다. 공식 지급물(`provided/`, `task.md`, `mark.md`, `mark*.sh`)은 수정하지 않는다.
2. KIT README의 `RUN guard` 절을 따른다 — 대상 Terraform 디렉터리로 이동한 뒤 `aws sts get-caller-identity`와 `aws configure get region`으로 지급 계정과 과제지 리전을 확인한다.
3. `terraform init` → `terraform validate` → `terraform plan`으로 기존 리소스의 의도치 않은 diff가 없는 것을 확인한 뒤에만 apply한다. `terraform init -upgrade`는 사용하지 않는다.
4. **VERIFY**는 KIT README의 기능 확인, **SCORE**는 해당 세트의 공식 `mark.md`와 `mark*.sh` 절차다. 둘을 서로 대신하지 않는다. 기본 RUN에 `destroy`를 넣지 않는다.

여기서 못 찾으면 `rg -i "<검색어>" KIT-INDEX.md shared/addons`로 내려간다. 공통 실패 대응은 [shared/TROUBLESHOOTING-COMMON.md](shared/TROUBLESHOOTING-COMMON.md)를 참조한다.
