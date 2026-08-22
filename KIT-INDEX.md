# KIT INDEX

과제지에서 **바뀐 문장 하나**를 찾은 뒤 30분 안에 코드로 옮기기 위한 역색인이다.

모든 KIT은 `shared/addons/`의 파일을 대상 세트로 **복사(COPY)**하는 방식이다. addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 세트의 Terraform state를 건드리지 않는다.

## 30분 루틴

| # | 하는 일 | 끝 조건 |
| --- | --- | --- |
| 1 | 바뀐 문장에서 **명사 하나**를 뽑는다 (`WAF`, `TTL`, `액세스 로그`, `CMK`) | 아래 표에서 KIT 1개 결정 |
| 2 | 그 KIT README를 연다 | `CHANGE` 표의 필수 변수 확인 |
| 3 | 코드 블록을 **블록 머리에 적힌 `*.tf` 파일**에 붙인다 | 세트 리소스 주소로 `<기존>` 치환 |
| 4 | 블록 밑 `<details>`에서 내 세트 항목을 편다 | `outputs.tf` 보강 + `terraform output` 값 확보 |
| 5 | `fmt` → `init` → `validate` → `plan` | **기존 리소스에 replace/delete 0건** |
| 6 | `apply` → KIT README `VERIFY` | 그 다음에만 세트 `mark.sh` |

`plan`에 기존 리소스 replace/delete가 뜨면 apply하지 않고 멈춘다. 이름이 충돌하면 기존 것을 지우지 말고 **KIT 쪽 변수를 리네임**한다.

## 1과제: 추가 문항은 이 5개에서만 나온다

필수 7개(VPC·Container·Database·Static hosting·ECR·로드밸런서·Application)는 이미 다 구현돼 있다. 새 문항은 **아직 안 쓰인 옵션 5개** 안에서 나온다.

| 옵션 | KIT | 첫 판단 |
| --- | --- | --- |
| **Observability** (가장 유력) | [observability](shared/addons/observability/README.md) | Container Insights = addon 한 줄 · 도구형(Grafana/Loki) = set-07 monitoring 복사 |
| **KMS** | [kms](shared/addons/kms/README.md) | 대상이 신규 리소스인지 기존 리소스인지 먼저 판별 (RDS·EBS·ECR·EKS는 생성 후 변경 불가) |
| **WAF** | [waf](shared/addons/waf/README.md) · [waf-extra-rules](shared/addons/waf-extra-rules/README.md) | Web ACL이 없다 → `waf` · 이미 있고 룰만 → `waf-extra-rules` |
| **Security (IAM/IRSA)** | [irsa](shared/addons/irsa/README.md) | 채점이 SA의 `role-arn` annotation을 읽으면 IRSA · 아니면 Pod Identity |
| **Lambda GET API** | [lambda-get-api](shared/addons/lambda-get-api/README.md) | set-07 / set-03 `lambda.tf` 가 더 가까운 재료다 |

1과제 금지선 — 넘는 요구는 오독이다: **인프라 스케일링 문항 없음**, 3rd-party Addon(Istio·Cilium·Calico·Crossplane·Nginx) 불가, Helm은 채점요소가 될 수 없다.

## 1과제: 꼬리 지시문 → 붙일 KIT

추가 문항 대부분은 새 모듈이 아니라 **기존 문항 뒤에 붙는 한 줄**이다. 문장에서 이 단어가 보이면 바로 그 KIT이다.

| 과제지에 새로 붙은 말 | KIT | 부착 파일 |
| --- | --- | --- |
| TTL · PITR · 스트림 · 온디맨드 백업 | [dynamodb-hardening](shared/addons/dynamodb-hardening/README.md) | `dynamodb.tf` |
| 버저닝 · 수명주기 · Object Lock · 퍼블릭 차단 · 버킷 정책 강화 | [s3-hardening](shared/addons/s3-hardening/README.md) | `s3.tf` |
| 액세스 로그 S3 저장 · 리스너 규칙 · 삭제 보호 · HTTP→HTTPS | [alb-hardening](shared/addons/alb-hardening/README.md) | `alb.tf` |
| 이미지 스캔 · 태그 불변성 · lifecycle policy · pull-through cache | [ecr-hardening](shared/addons/ecr-hardening/README.md) | `ecr.tf` |
| 지리적 제한 · 캐시 정책 · 에러 페이지 · 액세스 로그 | [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md) | `cloudfront.tf` |
| 동시성 제한 · Function URL · DLQ · 환경변수 암호화 | [lambda-hardening](shared/addons/lambda-hardening/README.md) | `lambda.tf` |
| 관리형 룰 그룹 · Rate limit · Geo 차단 · WAF 로깅 | [waf-extra-rules](shared/addons/waf-extra-rules/README.md) | `waf.tf` |
| CMK로 암호화 · 키 회전 · alias | [kms](shared/addons/kms/README.md) | `kms.tf` |
| Control Plane 로깅 · Secret 암호화 · IMDS 차단 | [eks-logging-variants](shared/addons/eks-logging-variants/README.md) | `eksctl/cluster.yaml` |
| 노드 자동 확장 · Karpenter · NodePool | [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md) | `eksctl/cluster.yaml`, `k8s/` |
| CloudWatch 경보 · SNS 알림 | [cw-alarms](shared/addons/cw-alarms/README.md) | `cloudwatch.tf` |
| CloudWatch 대시보드 | [cw-dashboard](shared/addons/cw-dashboard/README.md) | `cloudwatch.tf` |
| Logs Insights 쿼리 · 저장된 쿼리 | [cw-logs-insights](shared/addons/cw-logs-insights/README.md) | `cloudwatch.tf` |
| VPC 엔드포인트 · PrivateLink | [vpc-endpoints](shared/addons/vpc-endpoints/README.md) | `endpoints.tf` |
| VPC Flow Log | [vpc-flow-log](shared/addons/vpc-flow-log/README.md) | `flowlog.tf` |
| 감사 역할 · Cross-account audit | [iam-audit-role](shared/addons/iam-audit-role/README.md) | `iam.tf` |
| CloudTrail · 감사 추적 | [cloudtrail-hardening](shared/addons/cloudtrail-hardening/README.md) | `cloudtrail.tf` |
| Secrets Manager · 시크릿 회전 | [secrets-manager](shared/addons/secrets-manager/README.md) | `secrets.tf` |
| EventBridge 규칙 · GuardDuty 이벤트 | [eventbridge-security-rules](shared/addons/eventbridge-security-rules/README.md) | `eventbridge.tf` |
| Grafana 패널 · Prometheus Alert Rule | [grafana-panels](shared/addons/grafana-panels/README.md) | `k8s/monitoring/` |

## 2과제 전용 KIT

1과제 task-1에는 없는 서비스다. 2과제 모듈 카탈로그에 걸리면 여기서 시작한다.

| Keyword / phrase | KIT |
| --- | --- |
| RDS · RDS Proxy · Database connection | [rds-connection](shared/addons/rds-connection/README.md) |
| Client VPN · VPN | [client-vpn](shared/addons/client-vpn/README.md) |
| Keycloak · OIDC IdP · 외부 인증 | [keycloak](shared/addons/keycloak/README.md) |
| MSK · Kafka · Message Broker | [msk-hardening](shared/addons/msk-hardening/README.md) |
| DocumentDB | [docdb-hardening](shared/addons/docdb-hardening/README.md) |
| Kinesis · Firehose · 실시간 전송 | [kinesis-firehose](shared/addons/kinesis-firehose/README.md) |
| SQS · DLQ · 메시지 큐 | [sqs-hardening](shared/addons/sqs-hardening/README.md) |
| Step Functions · State Machine · Workflow | [sfn-hardening](shared/addons/sfn-hardening/README.md) |
| VPC Lattice · Service Network | [lattice-hardening](shared/addons/lattice-hardening/README.md) |
| ALB + Auto Scaling Group (EC2) | [ec2-asg-alb](shared/addons/ec2-asg-alb/README.md) |
| API Gateway 액세스 로그 · 스로틀 · Usage Plan | [apigw-hardening](shared/addons/apigw-hardening/README.md) |
| VPC 내 Lambda → RDS 조회 (task-3) | [lambda-vpc-rds](shared/addons/lambda-vpc-rds/README.md) |

## 세트별 리소스 주소 대조표 (task-1)

KIT 코드 블록의 `aws_xxx.<기존>` 자리에 넣을 값이다. **자기 세트 열만 본다.**

| 대상 | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 클러스터 이름 | `wskorea26-cluster` | `wsc2026-eks-cluster` | `unicorn-eks-cluster` |
| VPC | `aws_vpc.this` | `aws_vpc.this` | `aws_vpc.this` |
| 프라이빗 서브넷 | `aws_subnet.this[k]` (`local.private_subnet_keys`) | 동일 | 동일 |
| 프라이빗 라우트 테이블 | `aws_route_table.private` | `aws_route_table.app` | `aws_route_table.private` |
| S3 웹 버킷 | `aws_s3_bucket.web` | `aws_s3_bucket.static` | `aws_s3_bucket.web` |
| DynamoDB | `aws_dynamodb_table.data` | `aws_dynamodb_table.book` | `aws_dynamodb_table.concert` |
| ECR | `aws_ecr_repository.book` | `aws_ecr_repository.book` | `aws_ecr_repository.app` |
| Lambda | `aws_lambda_function.book` | `aws_lambda_function.book_get` | `aws_lambda_function.get_booking` |
| Lambda 실행 역할 | `aws_iam_role.book_lambda` | `aws_iam_role.book_function` | `aws_iam_role.get_booking` |
| 앱 ALB | `aws_lb.book` | **없음** — k8s Ingress(LBC 생성) | `aws_lb.app` (**internal**) |
| Grafana ALB | `aws_lb.grafana` | **없음** | `aws_lb.grafana` |
| 앱 리스너 | `aws_lb_listener.book` | **없음** | `aws_lb_listener.app` |
| 앱 타깃그룹 | `aws_lb_target_group.book` | **없음** | `aws_lb_target_group.app` |
| CloudFront | `aws_cloudfront_distribution.cdn` | `aws_cloudfront_distribution.cdn[0]` (`enable_cdn` count) | `aws_cloudfront_distribution.cdn` |
| WAF Web ACL | **없음** | `aws_wafv2_web_acl.wsc2026` (CLOUDFRONT) | `aws_wafv2_web_acl.unicorn` (CLOUDFRONT) |
| KMS 키 | `.eks` `.s3` `.dynamodb` | `.eks` `.db` `.ecr` `.bucket` `.function` | `.platform`(+`aws_kms_replica_key.platform_use1`) `.app` `.data` |
| 앱 로그 그룹 | `aws_cloudwatch_log_group.pod_logs` | `.book_app` | `.book_app` |
| Lambda 로그 그룹 | `.book_lambda` | `.book_function` | `.get_booking` |
| VPC 엔드포인트 | **없음** | `aws_vpc_endpoint.s3` | `.s3` + `.interface` |
| Flow Log | **없음** | **없음** | `aws_flow_log.this` |
| 앱 IAM 권한 방식 | **IRSA** — `aws_iam_policy.book_app` | **Pod Identity** — `aws_iam_role.book_pod` | **Pod Identity** — `aws_iam_role.book_app` |
| ALB↔Pod 연결 | TargetGroupBinding | k8s Ingress | TargetGroupBinding |

리전은 세 세트 모두 `ap-northeast-2`. CLOUDFRONT scope WAF 리소스만 us-east-1(`provider = aws.use1`).

## 헷갈리는 표현

| 과제지 표현 | 판단 기준 |
| --- | --- |
| **WAF** | Web ACL 자체가 없다 → [waf](shared/addons/waf/README.md) · 이미 있고 룰만 추가 → [waf-extra-rules](shared/addons/waf-extra-rules/README.md) |
| **로깅** | 컨테이너/애플리케이션 로그 → [observability](shared/addons/observability/README.md) · EKS Control Plane → [eks-logging-variants](shared/addons/eks-logging-variants/README.md) · VPC 트래픽 → [vpc-flow-log](shared/addons/vpc-flow-log/README.md) · API 호출 감사 → [cloudtrail-hardening](shared/addons/cloudtrail-hardening/README.md) |
| **스케일링** | EKS 노드 → [eks-scaling-variants](shared/addons/eks-scaling-variants/README.md) · EC2/ASG → [ec2-asg-alb](shared/addons/ec2-asg-alb/README.md) (**1과제에는 인프라 스케일링 문항이 출제되지 않는다** — 보이면 오독) |
| **Lambda** | REST API 뒤에 새로 만든다 → [lambda-get-api](shared/addons/lambda-get-api/README.md) · 기존 함수 강화 → [lambda-hardening](shared/addons/lambda-hardening/README.md) · VPC 안에서 RDS 조회(task-3) → [lambda-vpc-rds](shared/addons/lambda-vpc-rds/README.md) |
| **OIDC** | EKS Pod에 IAM 권한 → [irsa](shared/addons/irsa/README.md) · 외부 인증 IdP 구축 → [keycloak](shared/addons/keycloak/README.md) |
| **Grafana** | 스택을 새로 세운다 → [observability](shared/addons/observability/README.md) 경로 B · 이미 있는 스택에 패널/알림 룰만 → [grafana-panels](shared/addons/grafana-panels/README.md) |
| **지리적 제한** | CloudFront `restrictions` → [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md) · WAF `geo_match` → [waf-extra-rules](shared/addons/waf-extra-rules/README.md). **둘 다 걸지 않는다** — 채점이 어느 쪽을 읽는지 확인 |
| **암호화** | 신규 리소스 생성 시 → [kms](shared/addons/kms/README.md) 부착 블록 · 기존 RDS·EBS·ECR·EKS → **변경 불가**, 재생성 비용 대비 배점 판단 먼저 |

## 실행 전 공통 규칙

1. 해당 세트의 `task.md`·`mark.md`·`mark*.sh`·`NOTES.md`를 먼저 읽는다. 공식 지급물(`provided/`, `task.md`, `mark.md`, `mark*.sh`)은 수정하지 않는다.
2. KIT README의 `CHECK` 절로 계정·리전을 확인한 뒤 apply한다 — `aws sts get-caller-identity`, `aws configure get region`.
3. `terraform init` → `validate` → `plan`. `terraform init -upgrade`는 쓰지 않는다.
4. **VERIFY**(KIT README의 기능 확인)와 **SCORE**(세트 공식 `mark.md`·`mark*.sh`)를 서로 대신하지 않는다. 기본 RUN에 `destroy`를 넣지 않는다.

여기서 못 찾으면 `rg -i "<검색어>" KIT-INDEX.md shared/addons`로 내려간다. 공통 실패 대응은 [shared/TROUBLESHOOTING-COMMON.md](shared/TROUBLESHOOTING-COMMON.md).
