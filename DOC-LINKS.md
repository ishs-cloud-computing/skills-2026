# DOC-LINKS — 리소스별 문서·구현 색인

코드블록을 고칠 때 **무엇을 어느 순서로 여는가**의 색인이다.
대회장에는 AI 코딩 보조가 없고([DAY-OF](DAY-OF.md) 6절), 인터넷은 공식 문서와 AWS 웹 Q 만 열린다.
모르는 인자 하나를 3분에 찾느냐 20분에 찾느냐가 그대로 점수다.

**여는 순서는 항상 이 셋이다.**

| 순서 | 어디 | 언제 |
| --- | --- | --- |
| ① | **이 저장소의 기존 구현** | 거의 항상. 이미 apply 가 통과한 코드다 |
| ② | 로컬 스키마 명령 (`terraform providers schema`·`kubectl explain`·`helm show values`·`eksctl utils schema`·`aws ... help`) | 인자 **이름**만 기억 안 날 때. 인터넷 불필요 |
| ③ | 공식 문서 | 인자들을 **어떻게 조합**하는지 모를 때 (Example Usage) |

블로그·GitHub 이슈는 에러 메시지 원문으로만 검색한다. 인자 이름을 블로그에서 베끼면 프로바이더·차트 버전이 어긋난다.

같은 내용을 브라우저에서 볼 때는 학습 가이드의 두 페이지를 쓴다 — 저장소를 클론하기 전이나 CloudShell 에서 유용하다.

| 페이지 | 언제 |
| --- | --- |
| [검색 가이드](https://skills-2026-learn-module.vercel.app/reference/search-guide/) | 값의 종류로 진입하는 절차 전문 + 사이트별 검색 요령 · 훈련 드릴 |
| [치트시트](https://skills-2026-learn-module.vercel.app/reference/cheatsheet/) | 명령 자체가 기억 안 날 때 (kubectl·eksctl·helm·aws cli·terraform) |

---

## 1. 막힌 값의 종류로 진입한다

서비스 이름이 아니라 **값의 종류**로 판단한다.
같은 표의 확장판이 학습 가이드 [검색 가이드 — 막힌 값의 종류로 진입한다](https://skills-2026-learn-module.vercel.app/reference/search-guide/#%EB%A7%89%ED%9E%8C-%EA%B0%92%EC%9D%98-%EC%A2%85%EB%A5%98%EB%A1%9C-%EC%A7%84%EC%9E%85%ED%95%9C%EB%8B%A4) 에 있다.

| 막힌 것 | 저장소 안 | 로컬 명령 | 공식 문서 |
| --- | --- | --- | --- |
| HCL 리소스 인자·반환 속성 | `set-*/task-*/terraform/*.tf` | `terraform providers schema -json` | Terraform Registry 리소스 페이지 |
| Terraform 블록 문법·메타 인자 | 〃 | `terraform -help <명령>` | [Terraform 언어 문서](https://developer.hashicorp.com/terraform/language) |
| AWS CLI 플래그·출력 필드 | 각 `README.md` 의 검증 명령 | `aws <서비스> <명령> help` | [AWS CLI 레퍼런스](https://docs.aws.amazon.com/cli/latest/reference/) |
| 쿠버네티스·CRD YAML 필드 | `set-*/task-*/k8s/**` | `kubectl explain <경로>` | [Kubernetes API 레퍼런스](https://kubernetes.io/docs/reference/kubernetes-api/) · 프로젝트 문서 |
| helm 차트 values 키 | `**/*-values.yaml` | `helm show values <차트> --version <버전>` | [ArtifactHub](https://artifacthub.io/) |
| eksctl ClusterConfig 필드 | `set-*/task-*/eksctl/cluster.yaml` | `eksctl utils schema` | [schema.eksctl.io](https://schema.eksctl.io/) |
| IAM 액션·리소스·조건 키 | `terraform/iam.tf`·`kms.tf` | — | [Service Authorization Reference](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html) |
| `AccessDenied` 의 원인 | — | — | [정책 평가 로직](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html) |

## 2. 로컬 진입 명령 (인터넷이 막혔거나 느릴 때)

인자가 아니라 **명령 자체**가 기억 안 나면 학습 가이드 [치트시트 — 조회·진단 (막히면 이 순서)](https://skills-2026-learn-module.vercel.app/reference/cheatsheet/#%EC%A1%B0%ED%9A%8C%EC%A7%84%EB%8B%A8-%EB%A7%89%ED%9E%88%EB%A9%B4-%EC%9D%B4-%EC%88%9C%EC%84%9C) 를 먼저 본다. 아래는 스키마를 뽑는 명령만 추린 것이다.

```bash
export AWS_PAGER=""                      # 페이저 안 끄면 화면이 멈춘다

# Terraform — init 을 마친 디렉터리에서만 돈다
terraform providers schema -json > schema.json
jq -r '.provider_schemas["registry.terraform.io/hashicorp/aws"].resource_schemas.aws_lb_target_group.block.attributes  | keys[]' schema.json  # 단일 인자
jq -r '.provider_schemas["registry.terraform.io/hashicorp/aws"].resource_schemas.aws_lb_target_group.block.block_types | keys[]' schema.json  # 중첩 블록

# AWS CLI
aws cloudfront test-function help | grep -n -A4 -e "--if-match"

# 쿠버네티스 — 클러스터 연결은 필요, 인터넷은 불필요. CRD 도 똑같이 답한다
kubectl api-resources | grep -i targetgroup
kubectl explain targetgroupbinding.spec
kubectl explain nodepool.spec.disruption

# helm — 기본 values 를 파일로 떨구고 grep 으로 자른다
helm show values prometheus-community/kube-prometheus-stack --version <버전> > kps.yaml
grep -n -A5 adminPassword kps.yaml

# eksctl
eksctl utils schema > schema.json
jq -r '.definitions.ManagedNodeGroup.properties | keys[]' schema.json
```

로컬 스키마에는 Example Usage 가 없다. **조합**을 모를 때는 Registry 를 연다.

## 3. URL 규칙 — 검색창 대신 주소창

| 대상 | 주소 |
| --- | --- |
| Terraform 리소스 | `registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/<aws_ 뗀 이름>` |
| Terraform data 소스 | `.../docs/data-sources/<이름>` — 경로가 다르다. 리소스 쪽만 뒤지다 "그런 인자 없다"고 결론 내리는 실수가 여기서 난다 |
| AWS CLI | `docs.aws.amazon.com/cli/latest/reference/<서비스>/<명령>.html` |
| IAM 액션 목록 | `docs.aws.amazon.com/service-authorization/latest/reference/list_<서비스>.html` |
| helm 차트 | `artifacthub.io/packages/helm/<저장소>/<차트>` — 이름이 아니라 **저장소 URL** 로 고른다 |

> **버전이 다르면 인자도 다르다.** URL 의 `latest` 는 최신 프로바이더를 가리킨다.
> 이 저장소는 `versions.tf` 에서 `hashicorp/aws ~> 6.51` 을 쓴다. `terraform version` 이 찍는 실제 버전과
> 페이지 상단 버전 드롭다운을 맞춘다. helm 은 `--version` 을 고정해 뽑는다.

## 4. 리소스별 색인

`문서` 열의 Registry 링크는 전부 위 URL 규칙이다. `구현` 은 복사해 갈 실제 파일이다.

### 네트워크·연결

| 리소스·주제 | 문서 | 구현 | 고칠 때 막히는 곳 |
| --- | --- | --- | --- |
| `aws_vpc`·`aws_subnet`·`aws_route_table` | [vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | `set-07/task-1/terraform/vpc.tf` | 서브넷 `map_public_ip_on_launch`, EKS 서브넷 태그(`kubernetes.io/role/elb`) |
| `aws_security_group` vs `aws_vpc_security_group_*_rule` | [security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | `set-07/task-1/terraform/security.tf` | 인라인 `ingress` 와 별도 rule 리소스를 **섞으면 안 된다** |
| `aws_vpc_endpoint` | [vpc_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | `set-05/task-1/terraform/endpoints.tf` | Gateway(S3·DynamoDB)는 `route_table_ids`, Interface 는 `subnet_ids` + `private_dns_enabled` |
| `aws_lb`·`aws_lb_target_group`·`aws_lb_listener_rule` | [lb_target_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | `set-07/task-1/terraform/alb.tf` | `target_type = "lambda"` 면 `port`·`protocol`·`vpc_id` 를 **빼야** 한다 |
| VPC Lattice 7종 | [vpclattice_service_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network) · [사용 설명서](https://docs.aws.amazon.com/vpc-lattice/latest/ug/) | `set-08/task-2/module-2-lattice/terraform/lattice.tf`, `set-05/task-2/module-2-vpc-lattice/` | service network ↔ VPC ↔ service 세 association 을 다 걸어야 통신된다 |
| `aws_route53_zone`·`_record` | [route53_record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | `set-05/task-2/module-2-vpc-lattice/terraform/` | private zone 은 `vpc` 블록 필수 |
| `aws_flow_log` | [flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | `set-07/task-1/terraform/flowlog.tf` | 대상별 전송 IAM role 유무 |

### IAM·암호화·보안

| 리소스·주제 | 문서 | 구현 | 고칠 때 막히는 곳 |
| --- | --- | --- | --- |
| `aws_iam_role`·`aws_iam_policy` | [iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | `set-07/task-1/terraform/iam.tf` | Role 이름은 과제지 명시값 **정확 일치** — 채점 스크립트가 직접 읽는다 |
| 정책에 쓸 수 있는 액션·조건 키 | [Service Authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html) ([S3](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazons3.html) · [KMS](https://docs.aws.amazon.com/service-authorization/latest/reference/list_awskeymanagementservice.html)) | — | 표 3개(Actions·Resource types·Condition keys) 구조. 최소 권한 문항에서 쓴다 |
| `aws_kms_key`·`aws_kms_replica_key` | [kms_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) · [KMS 개발자 안내서](https://docs.aws.amazon.com/kms/latest/developerguide/) | `set-07/task-1/terraform/kms.tf` (CMK 3개·MRK·서비스별 key policy) | CloudFront scope 로그 암호화는 **us-east-1 키** 필요 → MRK |
| Pod Identity / IRSA / OIDC | [EKS 사용 설명서](https://docs.aws.amazon.com/eks/latest/userguide/) · [schema.eksctl.io](https://schema.eksctl.io/) | IRSA `set-08/task-2/module-4-*/eksctl/cluster.yaml`, Pod Identity `set-07/task-1/eksctl/cluster.yaml` | 채점이 SA 의 `eks.amazonaws.com/role-arn` **annotation 을 읽으면 IRSA** 고정 |
| `aws_secretsmanager_secret` | [secretsmanager_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | `task-3/terraform/rds-proxy.tf` | `recovery_window_in_days = 0` 이 없으면 같은 이름 재생성이 며칠 막힌다 |

### 스토리지·데이터베이스

| 리소스·주제 | 문서 | 구현 | 고칠 때 막히는 곳 |
| --- | --- | --- | --- |
| `aws_s3_bucket` + 부속 리소스 | [s3_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | `set-07/task-1/terraform/s3.tf` | 버저닝·암호화·퍼블릭차단은 **전부 별도 리소스**다 |
| `aws_dynamodb_table` | [dynamodb_table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) · [개발자 안내서](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/) | `set-07/task-2/module-1-nosql/terraform/`, `set-02/task-1/terraform/dynamodb.tf` | GSI 는 `attribute` 선언 필수, Stream 은 `stream_enabled` + `stream_view_type` |
| `aws_docdb_cluster`·`_cluster_instance` | [docdb_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/docdb_cluster) · [DocumentDB 안내서](https://docs.aws.amazon.com/documentdb/latest/developerguide/) | `set-08/task-2/module-1-nosql/terraform/docdb.tf` | 인스턴스는 별도 리소스, TLS 기본 on(앱에 CA 번들 필요) |
| `aws_db_instance`·`aws_db_proxy` | [db_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) · [RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html) | `task-3/terraform/rds.tf`·`rds-proxy.tf` | Proxy 는 Secrets Manager 시크릿 + IAM role 이 전제 |
| `aws_ecr_repository` | [ecr_repository](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | `set-07/task-1/terraform/ecr.tf` | 암호화는 **생성 시에만**. `IMMUTABLE_WITH_EXCLUSION` 은 provider 6.8.0+ |

### 컴퓨트·컨테이너

| 리소스·주제 | 문서 | 구현 | 고칠 때 막히는 곳 |
| --- | --- | --- | --- |
| eksctl `ClusterConfig` | [schema.eksctl.io](https://schema.eksctl.io/) | `set-07/task-1/eksctl/cluster.yaml`, `task-3/eksctl/cluster.yaml` | `eksctl utils schema` 로 필드명 확인. 버전 간 기본값이 바뀐다 |
| `aws_ecs_cluster`·`_service`·`_task_definition` | [ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) · [ECS 안내서](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/) | `set-08/task-1/terraform/ecs.tf`, `set-09/task-1/terraform/ecs.tf` | Execution Role 과 Task Role **분리**가 채점 항목 |
| `aws_instance`·user_data | [instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | `set-05/task-1/terraform/bastion.tf` + `bastion_user_data.sh.tpl` | 과제지가 요구하지 않은 EC2 는 **감점**. 3과제는 대수가 곧 점수 |
| `aws_cloudformation_stack` | [cloudformation_stack](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack) | `set-02/task-2/module-2-analytics/terraform/flink.tf` | Terraform 리소스가 없는 서비스를 감쌀 때의 탈출구 |

### 엣지 — CloudFront·WAF

| 리소스·주제 | 문서 | 구현 | 고칠 때 막히는 곳 |
| --- | --- | --- | --- |
| `aws_cloudfront_distribution` | [cloudfront_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) · [개발자 안내서](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/) | `set-07/task-1/terraform/cloudfront.tf` | 관리형 정책 ID 는 [data-sources/cloudfront_cache_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) 로 얻는다 |
| `aws_cloudfront_function`·`_key_value_store` | [cloudfront_function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | `set-07/task-2/module-2-cdn-function/terraform/functions.tf` | 검증은 `aws cloudfront test-function` (`--if-match` 에 ETag) |
| `aws_cloudfront_origin_access_control` | [cloudfront_origin_access_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | `set-07/task-1/terraform/cloudfront.tf` | 버킷 정책의 `AWS:SourceArn` 조건까지 맞아야 403 이 풀린다 |
| `aws_wafv2_web_acl` | [wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) · [WAF 안내서](https://docs.aws.amazon.com/waf/latest/developerguide/) | `set-07/task-1/terraform/waf.tf`(CLOUDFRONT), `task-3/terraform/waf.tf`(scope-down·base64) | `rate_based_statement` 상세는 페이지 안 별도 소제목. `evaluation_window_sec` 는 60/120/300/600 만 |

### 서버리스·이벤트·워크플로

| 리소스·주제 | 문서 | 구현 | 고칠 때 막히는 곳 |
| --- | --- | --- | --- |
| `aws_lambda_function`·`aws_lambda_permission` | [lambda_function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | `set-07/task-1/terraform/lambda.tf` + `lambda/` | ALB 가 호출하면 `principal = "elasticloadbalancing.amazonaws.com"` |
| `aws_lambda_event_source_mapping` | [lambda_event_source_mapping](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | `set-07/task-2/module-1-nosql/terraform/lambda.tf`, `set-02/task-2/module-3-msk/terraform/lambda.tf` | 소스(Stream·SQS·MSK)별로 필요한 IAM 액션이 다르다 |
| API Gateway (REST) | [api_gateway_rest_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api) · [안내서](https://docs.aws.amazon.com/apigateway/latest/developerguide/) | `set-05/task-2/module-4-rest-api/terraform/apigw.tf` | `aws_api_gateway_deployment` 에 `triggers` 가 없으면 변경이 배포에 안 실린다 |
| `aws_sfn_state_machine` | [sfn_state_machine](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) · [Step Functions](https://docs.aws.amazon.com/step-functions/latest/dg/) | `set-02/task-2/module-1-workflow/terraform/stepfunctions.tf` | ASL 정의는 `jsonencode`. 상태별 IAM 액션을 role 에 다 넣는다 |
| `aws_cloudwatch_event_rule`·`_target` | [cloudwatch_event_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | `set-08/task-2/module-3-event-handling/terraform/`, `shared/addons/eventbridge-security-rules/` | `event_pattern` 은 문자열 JSON. 대상 호출 권한은 별도 |
| `aws_cloudtrail`·`aws_config_config_rule` | [cloudtrail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail) · [Config](https://docs.aws.amazon.com/config/latest/developerguide/) | `shared/addons/cloudtrail-hardening/`, `shared/addons/eventbridge-security-rules/` | Config 는 recorder + delivery channel + status 3종이 한 세트 (set-02 구 module-3-event 은 RC 판에서 삭제 — git 이력) |
| `aws_sqs_queue`·`aws_sns_topic` | [sqs_queue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | `set-08/task-2/module-4-*/terraform/` | 큐 정책 없이는 SNS→SQS 가 안 붙는다 |

### 스트리밍·분석

| 리소스·주제 | 문서 | 구현 |
| --- | --- | --- |
| `aws_kinesis_stream` | [kinesis_stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_stream) | `set-02/task-2/module-2-analytics/terraform/kinesis.tf` |
| Managed Service for Apache Flink | [Flink 안내서](https://docs.aws.amazon.com/managed-flink/latest/java/) | `set-02/task-2/module-2-analytics/terraform/flink.tf` (CFN 래핑) |
| `aws_msk_cluster` | [msk_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/msk_cluster) · [MSK 안내서](https://docs.aws.amazon.com/msk/latest/developerguide/) | `set-02/task-2/module-3-msk/terraform/msk.tf` |

### 관측성

| 리소스·주제 | 문서 | 구현 | 고칠 때 막히는 곳 |
| --- | --- | --- | --- |
| `aws_cloudwatch_log_group`·`_metric_alarm`·대시보드 | [cloudwatch_metric_alarm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) · [CloudWatch 안내서](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/) | `set-07/task-1/terraform/cloudwatch.tf` | 대시보드를 콘솔에서 만들면 재현이 안 된다 — JSON 을 소스로 둔다 |
| Container Insights | [EKS 사용 설명서](https://docs.aws.amazon.com/eks/latest/userguide/) | `task-3/eksctl/cloudwatch-tuned.yaml` | `amazon-cloudwatch-observability` addon. `eks-pod-identity-agent` 가 전제 |
| Prometheus·Grafana | [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack) | `set-07/task-1/k8s/monitoring/` | 릴리스 밖 PodMonitor 를 잡으려면 selector 관련 values 키를 켠다 |
| Loki·LogQL | [ArtifactHub loki](https://artifacthub.io/packages/helm/grafana/loki) · [LogQL](https://grafana.com/docs/loki/latest/query/) | `set-07/task-2/module-4-*/`, `set-05/task-2/module-3-*/` | 차트 저장소(`grafana` vs `grafana-community`)와 버전이 세트마다 다르다 |
| Fluent Bit | [ArtifactHub fluent-bit](https://artifacthub.io/packages/helm/fluent/fluent-bit) | `set-07/task-1/k8s/logging/` | 로그 그룹 이름·리전만 교체 |
| PromQL | [PromQL 기초](https://prometheus.io/docs/prometheus/latest/querying/basics/) | `task-3/` | 3과제 운영 질의 |

### 쿠버네티스 오브젝트·CRD

내장 리소스는 [Kubernetes API 레퍼런스](https://kubernetes.io/docs/reference/kubernetes-api/), CRD 는 만든 프로젝트 문서를 본다.
**`kubectl explain` 은 CRD 도 똑같이 답한다** — 클러스터가 살아 있으면 이게 가장 빠르다.

| 리소스 | apiVersion | 문서 | 구현 |
| --- | --- | --- | --- |
| Deployment·Service·HPA | `apps/v1`·`v1`·`autoscaling/v2` | [Deployment v1](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/deployment-v1/) | `set-*/task-1/k8s/app/` |
| Ingress (ALB 어노테이션) | `networking.k8s.io/v1` | [Ingress annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/) | `set-*/task-1/k8s/` |
| TargetGroupBinding | `elbv2.k8s.aws/v1beta1` | [TargetGroupBinding](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/targetgroupbinding/targetgroupbinding/) | `set-07/task-1/k8s/app/targetgroupbinding.yaml`, `k8s/monitoring/grafana-targetgroupbinding.yaml` |
| ScaledObject·TriggerAuthentication | `keda.sh/v1alpha1` | [KEDA Scalers](https://keda.sh/docs/latest/scalers/) ([aws-sqs](https://keda.sh/docs/latest/scalers/aws-sqs/)) | `set-08/task-2/module-4-*/k8s/` |
| NodePool | `karpenter.sh/v1` | [Karpenter NodePool](https://karpenter.sh/docs/concepts/nodepools/) | `set-07/task-2/module-3-*/k8s/` |
| EC2NodeClass | `karpenter.k8s.aws/v1` | [Karpenter NodeClass](https://karpenter.sh/docs/concepts/nodeclasses/) | 〃 |
| PodMonitor·PrometheusRule | `monitoring.coreos.com/v1` | [prometheus-operator API](https://prometheus-operator.dev/docs/api-reference/api/) | `set-07/task-1/k8s/monitoring/` |

어노테이션(`alb.ingress.kubernetes.io/*`)은 스키마가 아니라 문자열이라 `kubectl explain` 이 못 잡는다. 위 문서에서 Ctrl+F 로 찾는다.

### helm 차트

`helm search repo <차트> --versions` 로 쓸 수 있는 버전을 먼저 본다. **차트 메이저가 바뀌면 `--set` 키가 움직인다.**

| 차트 | 저장소 | 이 저장소가 쓴 버전 |
| --- | --- | --- |
| aws-load-balancer-controller | `https://aws.github.io/eks-charts` | 세트별로 1.x / 3.x 가 갈린다 — 해당 세트 README 의 `--version` 을 그대로 쓴다 |
| kube-prometheus-stack | `https://prometheus-community.github.io/helm-charts` | set-07 task-1 README |
| keda | `https://kedacore.github.io/charts` | `2.20.1` |
| karpenter | `oci://public.ecr.aws/karpenter/karpenter` | `1.13.0` |
| loki | `https://grafana-community.github.io/helm-charts` | `18.1.1` |
| grafana | `https://grafana.github.io/helm-charts` | `8.15.0` / `10.5.15` |
| prometheus | `https://prometheus-community.github.io/helm-charts` | `29.13.0` |

## 5. 덧붙이기 스니펫 — 기존 문항을 건드리지 않고 얹는 것

당일 변동은 기존 문제 교체가 아니라 **문항 추가**다([DAY-OF](DAY-OF.md) 1·3절).
아래는 기존 리소스에 **한 줄~한 블록으로 붙는** 형태만 모았다. 붙인 뒤 `terraform plan` 으로 기존 리소스에 diff 가 없는지 확인하고 apply 한다.

> 1과제 옵션 5개(KMS·WAF·Security·Lambda GET API·Observability)의 전체 키트는 `add-addon-kit` 브랜치의
> `shared/addons/` 에 있다. 여기 있는 건 그중 **부착 지점**만 뽑은 것이다.

### 기존 리소스에 부착 가능한가

| 요구 | 부착 가능 | 비고 |
| --- | --- | --- |
| S3·DynamoDB·CloudWatch Logs 암호화 | 가능 | 별도 리소스/인자 추가로 끝 |
| ECR·RDS·EBS·EKS Secret 암호화 | **생성 시에만** | 재생성은 기존 채점 항목을 깨뜨린다 — 배점 보고 판단 |
| WAF 연결 | 가능 | CloudFront 는 배포에 한 줄, ALB 는 association 리소스 |
| VPC Flow Logs·Control Plane 로깅 | 가능 | VPC·클러스터 재생성 불필요 |
| 로그 보존 기간 | 가능 | Terraform 인자 또는 CLI 한 줄 |
| IRSA·Pod Identity | 가능 | `eksctl create ...` 로 부착. 클러스터 재생성 금지 |
| Container Insights | 가능 | addon 한 줄 |

### 암호화 부착

```hcl
# S3 — 기존 버킷에 붙는다
resource "aws_s3_bucket_server_side_encryption_configuration" "addon" {
  bucket = aws_s3_bucket.<기존>.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.addon.arn
    }
    bucket_key_enabled = true
  }
}

# DynamoDB — 기존 테이블 리소스 안에
server_side_encryption {
  enabled     = true
  kms_key_arn = aws_kms_key.addon.arn
}

# CloudWatch Logs — 기존 로그 그룹 리소스 안에
kms_key_id = aws_kms_key.addon.arn   # key policy 에 logs 서비스 문장이 없으면 apply 가 AccessDenied
```

키 정책 문장은 `set-07/task-1/terraform/kms.tf` 에서 그대로 가져온다(CloudWatch Logs·AutoScaling 문장 등).
노드 EBS 를 CMK 로 암호화하면 AutoScaling 서비스 연결 역할 문장이 없을 때 노드가 **조용히 부팅 실패**한다.

### WAF 연결

```hcl
# CloudFront — 배포 리소스에 한 줄. WebACL·로그 그룹은 전부 us-east-1(provider alias) 이어야 한다
web_acl_id = aws_wafv2_web_acl.addon.arn

# ALB / API Gateway — association 리소스로
resource "aws_wafv2_web_acl_association" "addon" {
  resource_arn = aws_lb.<기존>.arn
  web_acl_arn  = aws_wafv2_web_acl.addon.arn
}
```

로그 그룹 이름은 `aws-waf-logs-` 접두어가 강제된다.
관리형 룰 그룹은 `and_statement` 로 감쌀 수 없어 경로 한정은 `scope_down_statement` 로만 한다.

### 로깅·관측성 부착

```hcl
# VPC Flow Logs — 기존 VPC 에 붙는다
resource "aws_flow_log" "addon" {
  vpc_id               = aws_vpc.<기존>.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.addon.arn
  iam_role_arn         = aws_iam_role.addon_flowlog.arn
}
```

```powershell
# EKS Control Plane 로깅 — 클러스터 재생성 없이
eksctl utils update-cluster-logging --cluster <클러스터> --region <리전> --enable-types all --approve

# Container Insights
eksctl create addon --cluster <클러스터> --region <리전> --name amazon-cloudwatch-observability

# 로그 보존 기간이 과제지에 명시되면 (Container Insights 로그 그룹 기본값은 무제한)
aws logs put-retention-policy --log-group-name <이름> --retention-in-days <일수>
```

Grafana 노출은 새 ALB 를 만들지 말고 기존 ALB + TargetGroupBinding 을 재사용한다(불필요 리소스 감점 방지).

### Pod 권한 부착

```powershell
# IRSA — 채점이 SA annotation 을 읽을 때
eksctl utils associate-iam-oidc-provider --cluster <클러스터> --region <리전> --approve
eksctl create iamserviceaccount --cluster <클러스터> --region <리전> `
  --namespace <ns> --name <sa> --attach-policy-arn <POLICY_ARN> `
  --role-name <과제지_지정_Role_이름> --approve --override-existing-serviceaccounts

# Pod Identity — 기본값
eksctl create addon --cluster <클러스터> --region <리전> --name eks-pod-identity-agent
eksctl create podidentityassociation --cluster <클러스터> --region <리전> `
  --namespace <ns> --service-account-name <sa> --role-arn <ROLE_ARN>

kubectl rollout restart deployment/<이름> -n <ns>   # 부착 후 재시작해야 자격증명이 주입된다
```

검증:

```powershell
kubectl get sa <sa> -n <ns> -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
aws eks list-pod-identity-associations --cluster-name <클러스터> --region <리전>
kubectl exec deploy/<이름> -n <ns> -- aws sts get-caller-identity
```

### 모듈 5·6 추가

```powershell
Copy-Item -Recurse _template/task-2/module-4 set-XX/task-2/module-5-<name>
New-Item -ItemType Directory set-XX/task-2/provided/module-5
```

모듈 간 **리전이 겹치면 안 되고 리소스도 공유하면 안 된다**. 6모듈이면 배점이 모듈당 7.5 → 5.0 으로 재조정된다.

## 6. 구현이 없는 카탈로그 — 맨몸 진입점

2과제 모듈 카탈로그 13개 중 **8·9·10 은 완성 구현이 없다**([DAY-OF](DAY-OF.md) 3절).
이게 걸리면 시간을 여기에 먼저 배분한다. 아래가 가장 가까운 출발점이다.

### 8. RDS Connection — 사실상 재료가 있다

| 필요한 것 | 어디서 |
| --- | --- |
| RDS 인스턴스 + 서브넷 그룹 | `task-3/terraform/rds.tf` — 그대로 복사 |
| Secrets Manager + RDS Proxy + Proxy IAM role | `task-3/terraform/rds-proxy.tf` — 그대로 복사 |
| 문서 | [db_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) · [db_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_proxy) · [RDS Proxy 안내서](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html) |

복사한 뒤 손볼 것: `local.db_*` 값, **SG 인그레스가 `0.0.0.0/0` 이므로 VPC CIDR 로 좁힌다**(보안 채점),
`skip_final_snapshot`·`deletion_protection` 을 과제지 요구에 맞춘다. RDS 는 생성이 10분대다 — **가장 먼저 apply** 한다.

### 9. VPN — Client VPN

문서: [Client VPN 관리자 안내서](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/) ·
[ec2_client_vpn_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_client_vpn_endpoint)

리소스 4종이 한 세트다. 이름만 알면 인자는 Registry Example Usage 로 채운다.

```hcl
resource "aws_ec2_client_vpn_endpoint" "this" {
  client_cidr_block      = var.client_cidr      # VPC CIDR 와 겹치면 안 된다
  server_certificate_arn = var.server_cert_arn  # ACM
  authentication_options { ... }                # certificate-authentication | federated-authentication | directory-service-authentication
  connection_log_options { enabled = false }    # 로깅 요구되면 CloudWatch 로그 그룹 지정
  split_tunnel = true                           # 전체 터널이면 NAT 경로·비용이 늘어난다
}

resource "aws_ec2_client_vpn_network_association" "this" {}  # 연결할 서브넷마다 1개
resource "aws_ec2_client_vpn_authorization_rule"  "this" {}  # 대상 CIDR 인가
resource "aws_ec2_client_vpn_route"               "this" {}  # 인터넷 등 추가 경로가 필요할 때만
```

**시간 함정**: 상호 인증(certificate-authentication)이면 CA·서버·클라이언트 인증서를 만들어 ACM 에 넣어야 한다.
과제지가 인증 방식을 지정했는지 먼저 확인하고 인증서 발급 시간을 일정에 넣는다.
네트워크 association 은 생성이 느리다 — 먼저 걸어두고 다른 문항을 진행한다.

### 10. Keycloak — AWS 리소스가 아니다

문서: [Keycloak 문서](https://www.keycloak.org/documentation) ·
[컨테이너로 실행](https://www.keycloak.org/server/containers) ·
[모든 서버 옵션](https://www.keycloak.org/server/all-config)

AWS 쪽은 EC2·SG·(필요 시) ALB·RDS 뿐이라 `set-05/task-1/terraform/bastion.tf` + `bastion_user_data.sh.tpl` 을
EC2 + user_data 골격으로 복사한다. 나머지는 전부 Keycloak 설정이다.

- 관리자 계정 환경변수 이름이 **버전에 따라 다르다**(`KEYCLOAK_ADMIN` 계열 → `KC_BOOTSTRAP_ADMIN_*` 계열).
  추측하지 말고 배포할 태그로 확인한다: `docker run --rm quay.io/keycloak/keycloak:<태그> start-dev --help`
  또는 위 "모든 서버 옵션" 문서에서 Ctrl+F.
- `start-dev` 는 개발용(HTTP·임시 DB)이다. 과제지가 DB 연동·HTTPS 를 요구하면 `start` + `--db`·`--hostname` 계열 옵션으로 간다.
- 로컬 Docker 는 대회 PC 에 없다. 이미지 실행은 EC2 위에서 하고, 빌드가 필요하면 CloudShell 을 쓴다.
- IAM 연동을 요구하면 Keycloak 쪽 OIDC 클라이언트와 AWS 쪽 IAM Identity Provider 를 **양쪽 다** 만든다.

## 7. 값을 찾은 뒤

- 문서에서 얻은 인자는 **`terraform validate` → `plan`** 으로 즉시 확인한다. 문서가 맞아도 프로바이더 버전이 다르면 튕긴다.
- k8s 필드는 `kubectl apply --dry-run=server` 로 확인한다. client dry-run 은 CRD 스키마를 안 본다.
- 채점 대상 값(이름·수치·경로)의 정본은 문서가 아니라 **과제지·채점 스크립트**다. 문서는 문법만 준다.
- 같은 값을 두 번째 찾을 때 시간이 절반 아래로 안 줄면 경로가 아직 안 붙은 것이다 — 그 줄을 이 색인에 채워 넣는다.
