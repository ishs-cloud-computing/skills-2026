# KIT INDEX

과제지에서 **바뀐 문장 하나**를 찾은 뒤 30분 안에 코드로 옮기기 위한 역색인이다.

모든 KIT은 `shared/addons/`의 파일을 대상 세트로 **복사(COPY)**하는 방식이다. addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 세트의 Terraform state를 건드리지 않는다.

## 30분 루틴

**① 바뀐 문장에서 명사 하나를 뽑는다** (`WAF`·`TTL`·`액세스 로그`·`CMK`) → 아래 표에서 KIT 1개.
**② 그 KIT README를 열고 갈림길을 정한다** — `## FAST` 절이 있으면 A, 없으면 B.

| | **A · FAST** ([14개 KIT](#fast-경로--terraform-없이-붙일-수-있는-kit)) | **B · Terraform** (나머지) |
| --- | --- | --- |
| 무엇 | `aws` 명령 한두 줄로 속성을 켠다 | KIT 파일을 세트로 복사해 apply |
| 절차 | `CHANGE` 값 채우기 → FAST 명령 → `VERIFY` | `CHANGE` → 코드 블록을 **블록 머리에 적힌 `*.tf`** 에 붙이고 `<기존>` 치환 → 블록 밑 `<details>`에서 세트 항목 확인(`outputs.tf` 보강) → `fmt`·`init`·`validate`·`plan` → `apply` → `VERIFY` |
| 대략 | 1~2분 | 5~15분 + 리소스 생성 대기 |
| 대가 | terraform state 와 실물이 어긋난다 — 그 세트를 더 apply 하지 않는다 | 없음 |
| 못 쓰는 때 | 이름이 채점 대상인 IAM Role·Policy, 생성 시에만 지정되는 속성 | — |

**③ VERIFY 통과 뒤에만** 세트 `mark.sh` 를 돌린다. VERIFY 는 손으로 치지 말고 `..\..\..\shared\scripts\verify-kit.ps1 <kit> ...` 로 일괄 실행한다.

B 에서 `plan`에 기존 리소스 replace/delete가 뜨면 apply하지 않고 멈춘다. 이름이 충돌하면 기존 것을 지우지 말고 **KIT 쪽 변수를 리네임**한다.

### 코드 블록에서 바꿔야 하는 자리

꺾쇠 표기는 전부 치환 대상이다. 하나라도 남으면 `validate`에서 걸린다.

| 표기 | 넣을 값 | 어디서 얻나 |
| --- | --- | --- |
| `set-XX` | 자기 세트 디렉터리 (`set-02`·`set-03`·`set-05`·`set-07`·`set-08`·`set-09`) | — |
| `<기존>` | 기존 리소스의 Terraform 주소 이름 (`aws_s3_bucket.<기존>` → `aws_s3_bucket.web`) | 아래 [대조표](#세트별-리소스-주소-대조표-task-1). 표에 없는 세트는 [직접 찾는다](#표에-없는-세트는-직접-찾는다) |
| `<클러스터>` | EKS 클러스터 이름 | 같은 대조표 첫 행 |
| `<이름>` · `<룰이름>` · `<버킷>` | 과제지가 지정한 이름 | 과제지 원문 그대로 |
| `<region>` | 세트 리전 (task-1은 전부 `ap-northeast-2`) | `terraform.tfvars` |
| `<ns>` · `<sa>` · `<앱>` · `<svc>` | k8s 네임스페이스·ServiceAccount·앱·Service 이름 | `kubectl get ns` · 세트 `k8s/` |
| `<account_id>` | 지급 계정 ID | `aws sts get-caller-identity --query Account --output text` |
| `<id>` · `<sg-id>` · `<i-id>` | 실제 리소스 ID | `terraform output` 또는 `aws ... describe-*` |
| `<선수번호>` | 배정받은 선수 번호 | 과제지·좌석표 |

블록 안에 `# ← 세트별 주소로 치환` 주석이 붙어 있으면 그 줄이 치환 지점이다.

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

### 표에 없는 세트는 직접 찾는다

위 표는 task-1 이 있는 세트 중 셋만 채워져 있다. **set-05·set-08·set-09 는 표에 없고, 대회 당일 세트도 없다.**
표를 찾지 말고 자기 세트의 `.tf` 에서 바로 뽑는다 — 표보다 빠르고 어느 세트에서든 맞는다.

```powershell
# <기존> 자리에 넣을 Terraform 주소 이름
rg '^resource "aws_s3_bucket"' set-XX/task-1/terraform/      # -> resource "aws_s3_bucket" "web"  ->  web

# 이 세트가 가진 리소스 타입을 통째로 보고 싶을 때
rg -o '^resource "[a-z0-9_]+" "[a-z0-9_]+"' set-XX/task-1/terraform/ --no-filename | sort

# 이미 apply 했다면 state 가 가장 정확하다
terraform state list
```

`<클러스터>`(EKS 이름)·`<region>` 은 `terraform.tfvars` 와 `eksctl/cluster.yaml` 에 있고,
실제 리소스 **ID**(`vpc-`·`sg-`·ARN)는 [`discover.ps1`](#자가검사-스크립트) 이 리전별로 한 번에 뽑는다.

## 1과제 옵션 5개 — 세트별 사전 판정

분홍 항목을 보기 전에 이미 끝나 있는 것과 새로 붙일 것을 구분해 둔 표다. 표기는 세 가지다.

- **있음** — 코드에 이미 있다. 과제지 문구와 값만 대조하고 넘어간다.
- **신규** — 부착 KIT을 그대로 붙이면 된다. 기존 리소스는 건드리지 않는다.
- **재생성** — 생성 시에만 지정 가능한 속성이다. 이미 만들었으면 `plan`에 replace가 뜬다. 배점과 재생성 시간을 먼저 비교한다.

### Observability

| 항목 | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| Fluent Bit | 있음 — `k8s/monitoring/fluent-bit.yaml` (ns `monitoring`) | 있음 — `k8s/logging/fluent-bit.yaml` (ns `observability`) | 있음 — `k8s/logging/fluent-bit.yaml` (ns `logging`) |
| Prometheus / Grafana | 있음 — `k8s/monitoring/` | 있음 — `+ prometheus-rules.yaml` | 있음 — `+ cloudwatch-exporter-values.yaml` |
| Grafana 노출 | TargetGroupBinding (`aws_lb.grafana`) | k8s Ingress (LBC) | TargetGroupBinding (`aws_lb.grafana`) |
| Control Plane 로깅 | 있음 — 5종 전부 (`cluster.yaml`) | 있음 — 5종 전부 | 있음 — 5종 전부 |
| Container Insights addon | 신규 — `addons:`에 없음 | 신규 — `addons:`에 없음 | 신규 — `addons:`에 없음 |
| 앱 로그 그룹 | 있음 — `pod_logs` (보존 30일) | 있음 — `book_app` (보존 7일) | 있음 — `book_app`·`eks_cluster` (30일) |
| CloudWatch 경보·대시보드 | 신규 — 세 세트 모두 `aws_sns_topic`·`aws_cloudwatch_metric_alarm`·`aws_cloudwatch_dashboard` 없음 | 신규 | 신규 |

"모니터링 도구를 설치" 류면 셋 다 이미 서 있다 — 새로 세우지 말고 과제지가 요구한 지표·패널만 [grafana-panels](shared/addons/grafana-panels/README.md)로 얹는다. Container Insights를 이름으로 지정하면 그때만 addon을 추가한다.

### KMS

| 대상 | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 보유 키 | `.s3` `.dynamodb` `.eks` | `.db` `.ecr` `.eks` `.bucket` `.function` | `.platform`(+us-east-1 replica) `.app` `.data` |
| S3 | 있음 — SSE-KMS | 있음 | 있음 |
| DynamoDB | 있음 | 있음 | 있음 |
| ECR | **AWS 관리형 `aws/ecr`** — CMK 요구 시 재생성 | 있음 — `.ecr` CMK | 있음 — `.data` CMK |
| Lambda 환경변수·코드 | 신규 — `kms_key_arn` 없음 | 있음 — `kms_key_arn` + `source_kms_key_arn` | 있음 — `kms_key_arn` |
| CloudWatch 로그 그룹 | 신규 | 신규 | 있음 — `.platform` |
| EKS Secret 봉투 암호화 | 있음 — `secretsEncryption.keyARN` | 있음 | 있음 |
| 노드 EBS | `volumeEncrypted: true` (기본 키) — CMK 지정은 **재생성** | 동일 | 있음 — `volumeKmsKeyID` 지정 |

ECR·EKS Secret·노드 EBS는 생성 후 키를 바꿀 수 없다. 배포 전에 문항을 읽었다면 tfvars/`cluster.yaml`에서 먼저 지정하고, 이미 배포한 뒤라면 재생성 비용을 먼저 계산한다.

### WAF

| 항목 | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| Web ACL | **없음** → [waf](shared/addons/waf/README.md) 신규 | 있음 — `aws_wafv2_web_acl.wsc2026` (CLOUDFRONT) | 있음 — `aws_wafv2_web_acl.unicorn` (CLOUDFRONT) |
| us-east-1 provider alias | **없음** — CLOUDFRONT scope면 `provider "aws" { alias = "use1" }` 블록부터 추가 | 있음 — `providers.tf` | 있음 — `versions.tf` |
| CloudFront 연결 | 신규 | 있음 — `web_acl_id` | 있음 — `web_acl_id` |
| WAF 로깅 | 신규 | 신규 | 있음 |
| REGIONAL(ALB) 부착 | `aws_lb.book`에 association 신규 | **Terraform ALB가 없다** — Ingress 어노테이션 경로 | `aws_lb.app`(internal)에 association 신규 |

룰만 추가하는 문항이면 [waf-extra-rules](shared/addons/waf-extra-rules/README.md)이고, `priority` 충돌만 확인하면 된다.

### Security (IRSA / Pod Identity)

| 항목 | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 현재 방식 | **IRSA** — `iam.withOIDC: true` + `serviceAccounts` 3개 | **Pod Identity** — `podIdentityAssociations` | **Pod Identity** — `podIdentityAssociations` (addon에도 사용) |
| SA `role-arn` annotation | 있음 — eksctl이 생성 | **없음** — 매니페스트에 annotation 자체가 없다 | **없음** |
| 채점이 annotation을 읽으면 | 그대로 충족 | `iam.withOIDC: true` + `iam.serviceAccounts`로 전환 필요 (클러스터 업데이트) | 동일 |

채점 스크립트가 `eks.amazonaws.com/role-arn`을 읽는지부터 확인한다. 읽지 않으면 Pod Identity를 IRSA로 "정정"하지 않는다.

### Lambda GET API

| 항목 | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 함수 | `aws_lambda_function.book` | `.book_get` | `.get_booking` |
| 호출 경로 | ALB Lambda 타깃그룹 `wskorea26-lambda-tg` | Function URL (`AWS_IAM`) + CloudFront | ALB Lambda 타깃그룹 `unicorn-lambda-tg` |
| API Gateway | **세 세트 모두 없음** — "REST API"를 이름으로 요구하면 전부 신규 | 없음 | 없음 |

세 세트 모두 호출 경로가 동기라 Lambda `dead_letter_config`는 발화하지 않는다. DLQ 문항이면 비동기 경로부터 만든다.

## 여러 KIT을 한꺼번에 얹을 때

분홍 항목이 여러 개면 KIT을 하나씩 apply하지 않는다. **전부 붙인 뒤 `plan` 한 번**이 기본이다 — apply 횟수가 늘수록 기존 리소스를 건드릴 확률과 대기 시간이 같이 늘어난다.

### 부착 순서 (선행 KIT을 먼저 붙인다)

| 선행 | 후행 | 이유 |
| --- | --- | --- |
| [kms](shared/addons/kms/README.md) | s3-hardening · dynamodb-hardening · lambda-hardening · cw-alarms | 후행 블록이 키 ARN을 참조한다. 키가 없으면 `validate`부터 실패 |
| [cloudtrail-hardening](shared/addons/cloudtrail-hardening/README.md) | [eventbridge-security-rules](shared/addons/eventbridge-security-rules/README.md) | 세 세트 모두 CloudTrail이 없다. `AWS API Call via CloudTrail` 패턴 룰은 trail 없이는 발화하지 않는다 |
| [waf](shared/addons/waf/README.md) | [waf-extra-rules](shared/addons/waf-extra-rules/README.md) · cw-alarms의 WAF 알람 | Web ACL이 있어야 룰·지표가 붙는다 |
| [observability](shared/addons/observability/README.md) 경로 B | [grafana-panels](shared/addons/grafana-panels/README.md) | 패널은 기존 Grafana·Prometheus 위에만 올라간다 |
| [cw-alarms](shared/addons/cw-alarms/README.md) 0절 SNS 토픽 | 나머지 알람 블록 전부 | 알람의 `alarm_actions`가 토픽 ARN을 참조한다 |
| [alb-hardening](shared/addons/alb-hardening/README.md) 액세스 로그 버킷 | [s3-hardening](shared/addons/s3-hardening/README.md) | 로그 버킷까지 정책 대상이면 버킷을 먼저 만든다 |

Terraform 자체는 의존성을 그래프로 풀지만, **선행을 빼먹으면 `validate` 단계에서 정의되지 않은 참조로 멈춘다.** 순서는 붙이는 순서지 apply 횟수가 아니다.

### 같은 파일에 여러 KIT이 붙을 때

| 파일 | 겹치는 KIT | 확인할 것 |
| --- | --- | --- |
| `cloudwatch.tf` | cw-alarms · cw-dashboard · cw-logs-insights · kms(로그 그룹 암호화) | 같은 로그 그룹을 두 KIT이 새로 만들지 않는지. 기존 그룹에 인자만 추가한다 |
| `s3.tf` | s3-hardening · kms · alb-hardening(액세스 로그 버킷) · cloudtrail-hardening(trail 버킷) | 버킷 정책이 두 곳에서 선언되면 뒤엣것이 앞엣것을 덮는다. `aws_s3_bucket_policy`는 버킷당 하나로 합친다 |
| `waf.tf` | waf · waf-extra-rules · cw-alarms(BlockedRequests) | 룰 `priority` 중복 금지. 알람은 us-east-1 지표라 `provider = aws.use1` |
| `lambda.tf` | lambda-hardening · kms · lambda-get-api | 같은 함수에 `kms_key_arn`이 두 번 선언되지 않게 한다 |
| `iam.tf` | irsa · iam-audit-role · 각 KIT의 정책 | Role 이름이 과제지 지정값과 정확히 일치해야 한다. 정책은 합치지 말고 KIT별로 분리해 둔다 |
| `eksctl/cluster.yaml` | eks-logging-variants · eks-scaling-variants · irsa | **Terraform과 apply 축이 다르다.** 여기 변경은 `eksctl upgrade`/`update` 대상이며 일부는 클러스터 재생성이다. Terraform `plan`에 안 잡히니 따로 확인한다 |

### 묶어서 돌리는 절차

1. 분홍 항목마다 KIT을 정하고, 위 순서표대로 코드 블록을 **전부** 붙인다.
2. `terraform fmt` → `terraform validate`. 여기서 걸리는 건 대부분 선행 KIT 누락이다.
3. `terraform plan` 한 번. **기존 리소스에 replace/delete 0건**을 눈으로 확인한다.
4. replace가 뜨면 그 리소스를 만드는 KIT **하나만** 빼고 다시 `plan`한다. 남은 것부터 apply하고, 뺀 항목은 재생성 비용과 배점을 비교해 따로 판단한다.
5. `apply` 뒤 KIT별 `VERIFY`를 순서대로 돌린다. 전부 통과한 다음에만 세트 `mark.sh`를 돌린다.
6. `cluster.yaml`을 건드린 KIT이 있으면 Terraform과 별도로 eksctl 명령을 돌리고, `kubectl get nodes`로 클러스터가 살아 있는지 먼저 확인한다.

### 이름이 충돌하면

기존 리소스를 지우지 않는다. KIT 쪽 변수를 리네임한다. 충돌이 잦은 축은 아래와 같다.

| 축 | 리네임 대상 |
| --- | --- |
| S3 버킷 (전역 고유) | `bucket_suffix`, trail 버킷은 `trail_name` |
| CloudWatch 로그 그룹 | 로그 그룹 이름 변수 — 기존 그룹에 인자 추가로 대체 가능한지 먼저 본다 |
| IAM Role·Policy | **과제지가 이름을 지정했으면 리네임 금지.** 채점이 그 이름을 직접 읽는다 |
| KMS alias | `alias/` 뒤 접미사 |
| SNS 토픽·알람 | 이름 접미사 |

과제지가 이름을 지정한 리소스는 리네임 대상이 아니다. 그 이름으로 이미 뭔가 있으면 지우지 말고 감독에게 확인한다.

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

## FAST 경로 — terraform 없이 붙일 수 있는 KIT

채점은 **관찰 가능한 상태**만 본다 (`describe`·`jsonpath`·`curl`). terraform 코드나 만든 방식은 보지 않는다.
그래서 in-place 속성 변경으로 끝나는 문항은 파일 복사·`init`·`plan`·`apply` 없이 CLI 한두 줄이면 된다.
아래 14개 KIT README에는 `## FAST` 절이 있다.

| 왜 FAST 인가 | KIT |
| --- | --- |
| 테이블·버킷·리포지토리·함수 속성이 전부 in-place | [dynamodb-hardening](shared/addons/dynamodb-hardening/README.md#fast--terraform-없이-cli-로-붙이기) · [s3-hardening](shared/addons/s3-hardening/README.md#fast--terraform-없이-cli-로-붙이기) · [ecr-hardening](shared/addons/ecr-hardening/README.md#fast--terraform-없이-cli-로-붙이기) · [lambda-hardening](shared/addons/lambda-hardening/README.md#fast--terraform-없이-cli-로-붙이기) · [alb-hardening](shared/addons/alb-hardening/README.md#fast--terraform-없이-cli-로-붙이기) · [sqs-hardening](shared/addons/sqs-hardening/README.md#fast--terraform-없이-cli-로-붙이기) |
| 신규 리소스라 기존 것을 안 건드린다 | [vpc-flow-log](shared/addons/vpc-flow-log/README.md#fast--terraform-없이-cli-로-붙이기) · [vpc-endpoints](shared/addons/vpc-endpoints/README.md#fast--terraform-없이-cli-로-붙이기) · [cloudtrail-hardening](shared/addons/cloudtrail-hardening/README.md#fast--terraform-없이-cli-로-붙이기) · [secrets-manager](shared/addons/secrets-manager/README.md#fast--terraform-없이-cli-로-붙이기) |
| 개수만 많고 값만 다르다 | [cw-alarms](shared/addons/cw-alarms/README.md#fast--terraform-없이-cli-로-붙이기) · [cw-dashboard](shared/addons/cw-dashboard/README.md#fast--terraform-없이-cli-로-붙이기) · [cw-logs-insights](shared/addons/cw-logs-insights/README.md#fast--terraform-없이-cli-로-붙이기) |
| config 전체 교체지만 배포 replace 보다 싸다 (get → 수정 → `--if-match`) | [cloudfront-hardening](shared/addons/cloudfront-hardening/README.md#fast--terraform-없이-cli-로-붙이기) |

**대가는 하나다.** terraform state 와 실물이 어긋난다. CLI 로 붙인 세트에 이후 `apply` 를 걸면 되돌아간다.
그래서 규칙은 둘 중 하나다 — 그 세트를 더 apply 하지 않거나, 나중에 같은 값을 `.tf` 에도 넣는다.

FAST 명령이 요구하는 `<vpc-id>`·`<sg-id>`·`<ALB ARN>` 은 [`discover.ps1`](#자가검사-스크립트) 로 한 번에 뽑는다.

CloudFront 는 속성 하나만 바꾸는 API 가 없어 `get-distribution-config` → 수정 → `update-distribution --if-match` 세 줄이다.
**오리진·동작을 바꿨으면 `create-invalidation` 을 따로 친다** — 안 하면 배포는 `Deployed` 인데 채점은 캐시된 옛 응답을 본다.

**FAST 로 가지 않는 것**: 이름이 채점 대상인 IAM Role·Policy(terraform 이 안전),
WAF 룰(lock token + 전체 룰 배열 교체), KMS·EKS Secret 암호화·ECR CMK·Object Lock(생성 시에만 지정 가능 — CLI 로도 안 된다).

## 실행 전 공통 규칙

1. 해당 세트의 `task.md`·`mark.md`·`mark*.sh`·`NOTES.md`를 먼저 읽는다. 공식 지급물(`provided/`, `task.md`, `mark.md`, `mark*.sh`)은 수정하지 않는다.
2. KIT README의 `CHECK` 절로 계정·리전을 확인한 뒤 apply한다 — `aws sts get-caller-identity`, `aws configure get region`.
3. `terraform init` → `validate` → `plan`. `terraform init -upgrade`는 쓰지 않는다.
4. **VERIFY**(KIT README의 기능 확인)와 **SCORE**(세트 공식 `mark.md`·`mark*.sh`)를 서로 대신하지 않는다. 기본 RUN에 `destroy`를 넣지 않는다.

## 자가검사 스크립트

문서로만 있던 두 축을 명령으로 만든 것이다. 둘 다 `shared/scripts/` 에 있고 PowerShell 7 에서 그대로 돈다.

```powershell
# 계정에 실제로 있는 리소스 ID 를 리전별로 긁어 .env 로 떨군다 (읽기 전용).
shared\scripts\discover.ps1                       # 현재 리전 -> addon.<리전>.env
shared\scripts\discover.ps1 -Region ap-southeast-1
shared\scripts\discover.ps1 -SelfTest             # AWS 호출 없이 파싱 로직만 검사

# 붙인 KIT 의 VERIFY 블록을 일괄 실행한다. KIT 을 부착한 terraform 디렉터리에서 친다.
cd set-XX/task-1/terraform
..\..\..\shared\scripts\verify-kit.ps1 waf kms cw-alarms
..\..\..\shared\scripts\verify-kit.ps1                 # 인자 없이 = 실행 가능한 KIT 목록
..\..\..\shared\scripts\verify-kit.ps1 s3-hardening -DryRun   # 실행 대신 명령만 출력

# 제출 전 금지 조항·잔재 검사
shared\scripts\foul-check.ps1
shared\scripts\foul-check.ps1 -Regions ap-northeast-2,ap-southeast-1 -GraderPrincipal <채점 IAM User 이름>
```

`discover.ps1` 은 VPC·서브넷·라우트 테이블·SG·EKS(엔드포인트·OIDC·authenticationMode)·ALB(ARN·DNS·알람 dimension)·
타깃그룹·CloudFront(Comment 키)·DynamoDB·S3·Lambda·ECR·KMS alias·SNS·SQS·로그 그룹·running EC2 를 `KEY=value` 로 떨군다.
FAST 절의 `<vpc-id>`·`<sg-id>`·`<ALB ARN>` 자리에 그대로 넣는 값이다 — 대조표는 Terraform 주소라 CLI 로는 못 쓰고,
`terraform output` 은 `outputs.tf` 에 선언한 것만 나온다. 파일 머리에 bash·PowerShell 양쪽 로드 명령이 적혀 있으니
bastion·CloudShell 에 같이 올린다 (작업 규칙 6). 산출물은 `.gitignore` 대상이다.

`foul-check.ps1` 이 보는 것 — running EC2 개수와 목록(3과제는 적을수록 고득점, 작업용 bastion 잔재는 감점) ·
타 리전 EC2/EKS 잔재 · 고객 관리형 IAM 정책의 `"Action": "*"` / `"Principal": "*"` ·
`0.0.0.0/0` 인바운드 보안그룹 · EKS `authenticationMode` 와 access entry principal.

출력은 판단 재료다. 0 이 아니라고 전부 감점은 아니고, **과제지가 금지한 항목이 0 이 아니면 그 항목이 통째로 0점**이다.
명령으로 못 보는 것(이름 정확 일치·부하 테스트 중지·종이 과제지 금지 조항)은 [DAY-OF 9절](DAY-OF.md#9-채점-직전)에서 눈으로 확인한다.

여기서 못 찾으면 `rg -i "<검색어>" KIT-INDEX.md shared/addons`로 내려간다. 공통 실패 대응은 [shared/TROUBLESHOOTING-COMMON.md](shared/TROUBLESHOOTING-COMMON.md).
