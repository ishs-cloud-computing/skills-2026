# QUICK REFERENCE

과제지에서 **바뀐 문장**을 본 직후 30초 안에 KIT 하나를 고르는 카드. 전체 기준표는 [KIT-INDEX.md](KIT-INDEX.md).

## 1과제 추가 문항은 이 5개뿐

붙이기 전에 [세트별 사전 판정](KIT-INDEX.md#1과제-옵션-5개--세트별-사전-판정)에서 자기 세트 열을 본다 — 이미 있음 / 신규 / 재생성이 옵션별로 갈려 있다.

| 옵션 | KIT |
| --- | --- |
| **Observability** (가장 유력) | [observability](shared/addons/observability/README.md) |
| **KMS** | [kms](shared/addons/kms/README.md) |
| **WAF** | [waf](shared/addons/waf/README.md) (신규) · [waf-extra-rules](shared/addons/waf-extra-rules/README.md) (룰 추가) |
| **Security (IRSA/Pod Identity)** | [irsa](shared/addons/irsa/README.md) |
| **Lambda GET API** | [lambda-get-api](shared/addons/lambda-get-api/README.md) |

## 꼬리 지시문 → KIT → 붙일 파일

| 새로 붙은 말 | KIT | 파일 |
| --- | --- | --- |
| TTL · PITR · 스트림 | [dynamodb-hardening](shared/addons/dynamodb-hardening/README.md) | `dynamodb.tf` |
| 버저닝 · 수명주기 · 액세스 로그 | [s3-hardening](shared/addons/s3-hardening/README.md) | `s3.tf` |
| ALB 액세스 로그 · 삭제 보호 · 리스너 규칙 | [alb-hardening](shared/addons/alb-hardening/README.md) | `alb.tf` |
| 이미지 스캔 · 태그 불변성 · lifecycle | [ecr-hardening](shared/addons/ecr-hardening/README.md) | `ecr.tf` |
| 지리적 제한 · 에러 페이지 · 캐시 동작 | [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md) | `cloudfront.tf` |
| 동시성 · Function URL · DLQ | [lambda-hardening](shared/addons/lambda-hardening/README.md) | `lambda.tf` |
| 관리형 룰 · Rate limit · Geo 차단 | [waf-extra-rules](shared/addons/waf-extra-rules/README.md) | `waf.tf` |
| CMK 암호화 · 키 회전 | [kms](shared/addons/kms/README.md) | `kms.tf` |
| Control Plane 로깅 · Secret 암호화 · IMDS | [eks-logging-variants](shared/addons/eks-logging-variants/README.md) | `eksctl/cluster.yaml` |
| CloudWatch 경보 · SNS | [cw-alarms](shared/addons/cw-alarms/README.md) | `cloudwatch.tf` |
| CloudWatch 대시보드 | [cw-dashboard](shared/addons/cw-dashboard/README.md) | `cloudwatch.tf` |
| Logs Insights 쿼리 | [cw-logs-insights](shared/addons/cw-logs-insights/README.md) | `cloudwatch.tf` |
| VPC 엔드포인트 · PrivateLink | [vpc-endpoints](shared/addons/vpc-endpoints/README.md) | `endpoints.tf` |
| VPC Flow Log | [vpc-flow-log](shared/addons/vpc-flow-log/README.md) | `flowlog.tf` |
| 감사 Role · ExternalId | [iam-audit-role](shared/addons/iam-audit-role/README.md) | `iam.tf` |
| CloudTrail | [cloudtrail-hardening](shared/addons/cloudtrail-hardening/README.md) | `cloudtrail.tf` |
| Secrets Manager · 회전 | [secrets-manager](shared/addons/secrets-manager/README.md) | `secrets.tf` |
| EventBridge · GuardDuty · Config | [eventbridge-security-rules](shared/addons/eventbridge-security-rules/README.md) | `eventbridge.tf` |
| Grafana 패널 · PrometheusRule | [grafana-panels](shared/addons/grafana-panels/README.md) | `k8s/monitoring/` |

## 2과제 전용

MSK → [msk-hardening](shared/addons/msk-hardening/README.md) · DocumentDB → [docdb-hardening](shared/addons/docdb-hardening/README.md) · RDS → [rds-connection](shared/addons/rds-connection/README.md) · VPN → [client-vpn](shared/addons/client-vpn/README.md) · Keycloak → [keycloak](shared/addons/keycloak/README.md) · Lattice → [lattice-hardening](shared/addons/lattice-hardening/README.md) · Step Functions → [sfn-hardening](shared/addons/sfn-hardening/README.md) · Kinesis → [kinesis-firehose](shared/addons/kinesis-firehose/README.md) · SQS → [sqs-hardening](shared/addons/sqs-hardening/README.md) · EC2 ASG → [ec2-asg-alb](shared/addons/ec2-asg-alb/README.md) · API Gateway → [apigw-hardening](shared/addons/apigw-hardening/README.md) · EKS 스케일링 → [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md)

## 헷갈리면

| 표현 | 갈림길 |
| --- | --- |
| WAF | Web ACL 없다 → `waf` · 있고 룰만 → `waf-extra-rules` |
| 로깅 | 앱/컨테이너 → `observability` · Control Plane → `eks-logging-variants` · VPC 트래픽 → `vpc-flow-log` · API 감사 → `cloudtrail-hardening` |
| 지리적 제한 | CloudFront `restrictions` → `cloudfront-hardening` · WAF `geo_match` → `waf-extra-rules`. **둘 다 걸지 않는다** |
| 스케일링 | **1과제에는 인프라 스케일링 문항이 없다** — 보이면 오독 |

## 고른 뒤

KIT README의 `CHANGE` → 코드 블록(**블록 머리에 붙일 `*.tf` 파일이 적혀 있다**) → 블록 밑 `<details>` 에서 **자기 세트(set-02 / set-03 / set-07)** 항목을 펴서 `outputs.tf` 보강 + `terraform output` 값 확보 → `fmt` → `init` → `validate` → `plan`(기존 리소스 replace/delete 0건) → `apply` → `VERIFY` → 세트 `mark.sh`.

세트별 리소스 주소는 [KIT-INDEX 대조표](KIT-INDEX.md#세트별-리소스-주소-대조표-task-1).

## KIT이 2개 이상이면

하나씩 apply하지 않는다. 전부 붙이고 `plan` 한 번, 기존 리소스 replace/delete 0건 확인 후 apply한다.

선행부터 붙인다: `kms` → 암호화 인자를 쓰는 KIT · `cloudtrail-hardening` → `eventbridge-security-rules` · `waf` → `waf-extra-rules` · `observability` → `grafana-panels` · `cw-alarms` SNS 토픽 → 나머지 알람.

같은 파일이 겹치는 조합(`cloudwatch.tf`·`s3.tf`·`waf.tf`·`lambda.tf`·`iam.tf`·`cluster.yaml`)과 replace가 떴을 때 빼는 순서는 [여러 KIT을 한꺼번에 얹을 때](KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때).

`cluster.yaml`을 건드리는 KIT은 Terraform `plan`에 잡히지 않는다 — eksctl 쪽에서 따로 확인한다.
