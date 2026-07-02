# set-08 / task-1 설계 (Solution Architecture)

ECS Fargate로 Book API(Go/Gin)를 배포하고, CloudFront 단일 엔드포인트로 S3 정적 페이지와 `/v1/*` API를 함께 서비스하는 과제. 전 리소스 ap-northeast-2, IaC는 Terraform 단일 스택(EKS 없음 → `eksctl/`, `k8s/` 불필요).

```
사용자 ──> CloudFront (skills-book-cloudfront)
             ├─ Default behavior ──> S3 (OAC, skills-book-static-2026-<비번호>)  : index.html, main.jpeg
             └─ /v1/*  behavior ──> ALB (internet-facing, HTTP 80)
                  └─ Listener Rule: X-Origin-Verify 일치 → TG(ip, 8080, /health)
                     Default Rule: 403 Fixed Response
                        └─> ECS Fargate Service (desired 2, Private Subnet, Public IP 없음)
                              └─> DynamoDB skills-book-booking (KMS CMK alias/skills-book-ddb)
                                   * Gateway VPC Endpoint 경유
CloudWatch: /ecs/skills-book-app 로그 → 4xx/5xx Metric Filter → Alarm
```

## 1. 요구사항 ↔ 채점항목 ↔ 리소스 매핑

| 채점 | 배점 | 리소스(Terraform) | 핵심 판정 기준 |
|---|---|---|---|
| 1-1 VPC | 1.0 | `aws_vpc` | Name tag `skills-book-vpc`, DNS Hostnames/Resolution true |
| 1-2 Subnet | 1.0 | `aws_subnet` ×4 | Public 2 + Private 2, 서로 다른 AZ |
| 1-3 Public Routing | 1.0 | `aws_route_table`, `aws_internet_gateway` | Public RT에 0.0.0.0/0 → IGW |
| 1-4 NAT/Endpoint | 1.0 | `aws_nat_gateway` ×2 | Private에서 ECR pull·Logs·AWS API 가능 |
| 1-5 DDB Endpoint | 1.0 | `aws_vpc_endpoint` (Gateway) | `com.amazonaws.ap-northeast-2.dynamodb`, Private RT 연결 |
| 2-1 S3+CF | 1.5 | `aws_s3_bucket`, `aws_s3_object` ×2, `aws_cloudfront_distribution` | index.html/main.jpeg 존재, CF 도메인 200 |
| 2-2 BPA | 1.0 | `aws_s3_bucket_public_access_block` | 4옵션 true, 직접 접근 200 아님, **버킷 Name tag 출력됨** |
| 2-3 OAC | 1.5 | `aws_cloudfront_origin_access_control`, `aws_s3_bucket_policy` | OriginAccessControlId 존재, 버킷 정책 SourceArn=배포 ARN |
| 2-4 라우팅 | 1.0 | distribution behaviors | Default→S3, `/v1/*`→ALB, POST 허용 |
| 3-1 ALB/TG | 1.5 | `aws_lb`, `aws_lb_target_group` | internet-facing, ip 타입, 8080, `/health`, healthy target |
| 3-2 Custom Header | 1.0 | distribution ALB origin custom_header | `X-Origin-Verify` 값 20자 이상 |
| 3-3 Header 차단 | 1.5 | `aws_lb_listener`, `aws_lb_listener_rule` | 직접 `/health` 403, 헤더 포함 200 |
| 4-1 ECR | 1.5 | `aws_ecr_repository` | Name tag `skills-book-ecr`, 이미지 ≥1 |
| 4-2 Task Def | 1.5 | `aws_ecs_task_definition` | family/FARGATE/awsvpc/CPU·Mem/컨테이너명/8080/env/awslogs |
| 4-3 Service | 1.5 | `aws_ecs_cluster`, `aws_ecs_service` | desired 2, TG 연결, Public IP DISABLED, Private Subnet |
| 4-4 API 동작 | 1.5 | (통합) | CF 경유 POST → booking_id 반환, DDB 저장 |
| 5-1 DDB Table | 1.0 | `aws_dynamodb_table` | `skills-book-booking`, PK `booking_id`(S) |
| 5-2 KMS CMK | 1.5 | `aws_kms_key`, `aws_kms_alias` | `alias/skills-book-ddb`, 테이블 SSE가 해당 CMK |
| 5-3 Execution Role | 1.0 | `aws_iam_role` execution | Task Def에 연결 |
| 5-4 Task Role | 1.5 | `aws_iam_role` task | 연결 + Execution Role과 상이 |
| 6-1 Logs | 1.5 | `aws_cloudwatch_log_group` | `/ecs/skills-book-app`, stream prefix `book` |
| 6-2 Metric Filter | 1.5 | `aws_cloudwatch_log_metric_filter` ×2 | 이름/Namespace/Metric명/Value=1 |
| 6-3 Alarm | 1.5 | `aws_cloudwatch_metric_alarm` ×2 | Sum, ≥1, 60s, 1/1 |
| 6-4 Alarm 세부 | 0.5 | (동일) | TreatMissingData=notBreaching |

## 2. 디렉토리 구조

```
set-08/task-1/
├── terraform/
│   ├── providers.tf        # provider(hashicorp/aws 고정 버전), required_version
│   ├── variables.tf        # 기본값
│   ├── terraform.tfvars    # 비번호 등 세트 값 주입
│   ├── vpc.tf              # VPC·Subnet·IGW·NAT·RT·DDB Endpoint
│   ├── s3.tf               # 버킷·BPA·정책·정적 객체 업로드
│   ├── cloudfront.tf       # OAC·Distribution
│   ├── alb.tf              # ALB·TG·Listener·Rule·SG
│   ├── ecr.tf              # Repository
│   ├── ecs.tf              # Cluster·Task Definition·Service·Task SG
│   ├── iam.tf              # Execution/Task Role·Policy
│   ├── dynamodb.tf         # KMS Key·Alias·Table
│   ├── cloudwatch.tf       # Log Group·Metric Filter·Alarm
│   └── outputs.tf          # CF 도메인, ECR URL, ALB DNS 등
├── app/
│   └── Dockerfile          # 빌드 컨텍스트는 shared/provided/task-1 (원본 수정 금지)
├── plan.md · task.md · mark.md · mark.sh
└── README.md               # 런북 (구현 시 작성)
```

## 3. 도메인별 설계

### 3.1 VPC (vpc.tf)

- CIDR `10.0.0.0/16` (변수), DNS Hostnames/Resolution 모두 활성화, Name tag `skills-book-vpc`.
- Subnet: Public `10.0.0.0/24`, `10.0.1.0/24` (2a/2b) / Private `10.0.10.0/24`, `10.0.11.0/24` (2a/2b). AZ·CIDR 모두 변수.
- IGW 1개, Public RT: 0.0.0.0/0 → IGW.
- NAT Gateway 2개(AZ당 1개, 고가용성 요구 충족) + Private RT 2개(각각 자기 AZ NAT로 0.0.0.0/0). 개수는 변수(`nat_gateway_count`)로 두어 비용 절감 시 1개로 축소 가능.
- DynamoDB Gateway Endpoint: `com.amazonaws.ap-northeast-2.dynamodb`(리전 변수 조합), Private RT 2개에 연결. 채점 1-5가 Gateway 타입 + 서비스명을 명시 검사.
- NAT가 있으므로 ECR/Logs Interface Endpoint는 만들지 않는다(불필요 리소스 감점 회피, 채점 1-4는 NAT만으로 충족).

### 3.2 S3 (s3.tf)

- 버킷 `skills-book-static-2026-<비번호>` — 비번호는 변수 `bibunho`.
- **Name tag를 버킷명과 동일하게 부여** — mark.sh 2-2가 `get-bucket-tagging`으로 Name tag 값을 출력한다.
- Public Access Block 4옵션 전부 true.
- 버킷 정책: `Principal: cloudfront.amazonaws.com` + `Condition: AWS:SourceArn = <distribution ARN>`으로 `s3:GetObject` 허용 (OAC 표준 정책).
- `aws_s3_object`로 index.html(`content_type = "text/html"`)·main.jpeg(`content_type = "image/jpeg"`) 업로드. source는 `../../../shared/provided/task-1/`. content_type 누락 시 브라우저 확인(채점 유의사항 2)에서 다운로드로 처리될 수 있으므로 필수.

### 3.3 CloudFront (cloudfront.tf)

- Distribution **Name tag `skills-book-cloudfront` 필수** — mark.sh가 Name tag + S3 origin 포함 여부로 배포를 식별한다. 태그 누락 시 2~4번 항목 연쇄 실패.
- OAC: sigv4 / always signing, S3 origin에 연결.
- Origin 1: S3 REST 도메인(`bucket.s3.ap-northeast-2.amazonaws.com`), OAC 적용.
- Origin 2: ALB DNS, `custom_origin_config` http-only, port 80.
  - custom_header `X-Origin-Verify` = `random_password`(length 32, special=false) 값. 20자 이상 요구를 변수 기본값으로 보장하고, listener rule과 동일 참조로 불일치를 원천 차단.
- Default behavior → S3 origin, viewer-protocol redirect-to-https, Managed-CachingOptimized.
- Ordered behavior `/v1/*` → ALB origin, **allowed methods 7종 전체(POST 포함)**, Managed-CachingDisabled + Managed-AllViewerExceptHostHeader(origin request policy). API 캐시 금지 + 헤더/쿼리 전달.
- `default_root_object = "index.html"` — mark.sh 2-1이 `https://<domain>/` 로 200을 확인.
- Viewer certificate: CloudFront 기본 인증서.

### 3.4 ALB (alb.tf)

- internet-facing, Public Subnet 2개, HTTP:80 listener.
- **ALB SG는 80을 0.0.0.0/0에 개방해야 한다.** mark.sh 3-3이 CloudShell에서 ALB DNS로 직접 curl 하여 403(기본 룰)과 200(헤더 포함)을 확인하므로, CloudFront prefix list로 좁히면 타임아웃이 나서 1.5점을 잃는다. 접근 통제는 SG가 아니라 헤더 검증 listener rule이 담당 — 의도된 0.0.0.0/0이므로 리뷰 시 예외 처리.
- Listener default action: fixed-response 403 (text/plain).
- Listener rule priority 1: `http_header X-Origin-Verify == <헤더 값>` → TG forward.
- Target Group: type ip, HTTP 8080, health check path `/health`(200), interval 15s / healthy_threshold 2로 대회 중 빠른 healthy 전환.

### 3.5 ECR + 컨테이너 이미지 (ecr.tf, app/Dockerfile)

- Repository 이름·Name tag 모두 `skills-book-ecr` (mark.sh는 tag ARN 마지막 세그먼트를 repo명으로 사용하므로 이름=태그로 통일해야 안전).
- 제공 book 바이너리는 **정적 링크 x86-64 ELF** (file로 확인) → Task Definition `runtime_platform`은 X86_64 필수.
- Dockerfile (base 버전 고정, Docker Hub rate limit 회피를 위해 ECR Public 미러 사용):

```dockerfile
FROM public.ecr.aws/docker/library/alpine:3.23
RUN apk add --no-cache ca-certificates        # AWS API TLS 통신용
COPY book /app/book
RUN chmod +x /app/book
EXPOSE 8080
ENTRYPOINT ["/app/book"]
```

- 빌드 컨텍스트는 `shared/provided/task-1/` (원본 그대로 사용, 복사·수정 금지): `docker build -f app/Dockerfile -t <ECR_URL>:v1 ../../shared/provided/task-1`. 태그는 `v1` 고정(latest 금지).

### 3.6 ECS Fargate (ecs.tf)

- Cluster: 이름·Name tag `skills-book-cluster` (mark.sh가 resourcegroupstaggingapi 태그 검색으로 식별 — 태그 필수).
- Task Definition:
  - family `skills-book-task`, FARGATE / awsvpc, **cpu 256 / memory 512** (최소 사양 요구).
  - runtime_platform: LINUX / X86_64.
  - 컨테이너 `skills-book-container`, image `<ECR_URL>:v1`, containerPort 8080.
  - env: `AWS_REGION=ap-northeast-2`, `TABLE_NAME=skills-book-booking` (둘 다 변수 참조, 대소문자 정확히).
  - logConfiguration: awslogs → group `/ecs/skills-book-app`, region, stream-prefix `book`.
- Service: 이름·Name tag `skills-book-service`, launch_type FARGATE, desired 2, Private Subnet 2개, `assign_public_ip = false`, TG 연결(container 8080), health_check_grace_period ~30s, deployment circuit breaker(rollback 없이 감지만) 선택.
- Task SG: inbound 8080 ← ALB SG만. outbound all (NAT·DDB Endpoint 경유).

### 3.7 DynamoDB + KMS (dynamodb.tf)

- KMS Key: Customer Managed, alias `alias/skills-book-ddb`. 키 정책은 기본(계정 root 위임)으로 두어 채점 IAM Role의 describe/scan이 막히지 않게 한다.
- Table `skills-book-booking`: PAY_PER_REQUEST, hash_key `booking_id`(S). **attribute 정의는 booking_id 하나만** — 나머지(client_id 등)는 아이템 속성이라 정의 불가/불필요.
- `server_side_encryption { enabled = true, kms_key_arn = <CMK> }`.

### 3.8 IAM (iam.tf)

- Execution Role `skills-book-ecs-execution-role`: 신뢰 `ecs-tasks.amazonaws.com`, 관리형 `AmazonECSTaskExecutionRolePolicy`(ECR pull + Logs push).
- Task Role `skills-book-ecs-task-role`: 신뢰 동일, 인라인 최소 권한 —
  - `dynamodb:PutItem` on 테이블 ARN (앱은 PutItem만 수행, 로컬 실행으로 확인).
  - `kms:Decrypt`, `kms:GenerateDataKey`, `kms:DescribeKey` on CMK ARN — CMK 암호화 테이블 접근 시 호출 주체에 KMS 권한 필요.
- 두 Role은 반드시 상이 (5-4가 명시 비교).

### 3.9 CloudWatch (cloudwatch.tf)

- Log Group `/ecs/skills-book-app` 명시 생성(retention 7일 — 감점 없는 정리 목적), Task Definition보다 먼저 존재하도록 의존 관계 설정.
- **앱 로그 형식 (book 바이너리 로컬 실행으로 확인한 실측값):**

```
Server running on port 8080
2026/07/02 08:52:14 access method=GET path=/health status=200 duration=129.699µs remote_addr=[::1]:38602 user_agent="curl/8.18.0"
2026/07/02 08:52:15 access method=GET path=/nope status=404 duration=31.994µs remote_addr=[::1]:38616 user_agent="curl/8.18.0"
2026/07/02 08:52:15 access method=POST path=/v1/book status=500 duration=177.5ms remote_addr=... user_agent="curl/8.18.0"
```

  공백 구분 필드: `날짜 시각 access method=… path=… status=NNN …` → 6번째 토큰이 `status=NNN`.
- Metric Filter (standalone 정규식 패턴 — 공식 문서로 확인한 문법):
  - `skills-book-4xx-filter`: `%status=4[0-9][0-9]%`
  - `skills-book-5xx-filter`: `%status=5[0-9][0-9]%`
  - Namespace `Skills/CloudComputing/Task1`, metric name `skills-book-4xx-count`/`skills-book-5xx-count`, value `1`.
  - space-delimited 패턴의 후미 ellipsis(`[a, b, ...]`)는 공식 문서에 예시가 없어(선두 `[..., a, b]`만 문서화) 회피했다. 정규식 패턴은 문서상 명시 지원이며 로그 그룹당 최대 5개 제한(여기선 2개)만 유의.
  - `DynamoDB put error: … StatusCode: 400 …` 라인은 `status=` 소문자 리터럴 불일치로 매칭되지 않는다 (필터 패턴은 대소문자 구분).
  - 배포 후 실제 로그 이벤트로 `aws logs test-metric-filter` 검증(작업 규칙 3).
- Alarm ×2 (`skills-book-4xx-alarm`, `skills-book-5xx-alarm`): 해당 metric, Statistic Sum, `GreaterThanOrEqualToThreshold` 1, Period 60, EvaluationPeriods 1, DatapointsToAlarm 1, TreatMissingData notBreaching. 액션 불필요.

## 4. 변수 설계 (30% 변동 대비)

`variables.tf` 기본값 + `terraform.tfvars` 주입:

| 변수 | 기본값 | 비고 |
|---|---|---|
| `bibunho` | (tfvars 필수) | S3 버킷명 suffix |
| `region` | `ap-northeast-2` | env AWS_REGION·엔드포인트 서비스명에도 사용 |
| `name_prefix` | `skills-book` | 전 리소스명 파생 (`{prefix}-vpc` 등) — 이름 체계 일괄 변경 대비 |
| `vpc_cidr` / `public_subnet_cidrs` / `private_subnet_cidrs` | 10.0.0.0/16 외 | CIDR 변경 대비 |
| `azs` | `["apne2-a","apne2-b"]` 형태 | AZ 변경 대비 |
| `nat_gateway_count` | 2 | 비용/HA 트레이드오프 |
| `container_port` | 8080 | TG·SG·Task Def 공유 |
| `task_cpu` / `task_memory` | 256 / 512 | 사양 변경 대비 |
| `desired_count` | 2 | |
| `image_tag` | `v1` | |
| `table_name` | `skills-book-booking` | env TABLE_NAME과 단일 소스 |
| `origin_verify_header` | `X-Origin-Verify` | 헤더명 변경 대비 (값은 random_password) |

고정 리소스명은 전부 `name_prefix` 파생 + local로 모아 채점지와 1:1 대조 가능하게 구성한다.

## 5. 배포 순서 (README 런북 초안)

ECS Service가 이미지 없이는 안정화되지 않으므로 ECR 선행 → 이미지 push → 전체 apply 순서.

```bash
# 1. ECR만 먼저 생성
cd set-08/task-1/terraform
terraform init
terraform apply -target=aws_ecr_repository.book

# 2. 이미지 빌드·푸시 (본 컴퓨터, x86_64)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com
docker build -f ../app/Dockerfile -t <ECR_URL>:v1 ../../../shared/provided/task-1
docker push <ECR_URL>:v1

# 3. 전체 apply (S3 객체 업로드 포함, CloudFront 배포 5~10분 소요)
terraform apply

# 4. 안정화 확인
aws ecs wait services-stable --cluster skills-book-cluster --services skills-book-service --region ap-northeast-2
curl -I https://$(terraform output -raw cloudfront_domain)/index.html

# 5. 셀프 채점
cd .. && BIBUNHO=<비번호> bash mark.sh
```

bastion 없음 — 이 과제는 전 과정 본 컴퓨터 + (채점만) CloudShell.

## 6. 함정·주의사항 (채점 스크립트 실측 기반)

1. **태그로 식별되는 리소스 4종**: CloudFront(`skills-book-cloudfront`), ECR(`skills-book-ecr`), ECS Cluster/Service. Name tag 누락 시 mark.sh가 리소스 자체를 못 찾아 해당 영역 전체가 0점. S3 버킷 Name tag도 2-2에서 출력된다.
2. **ALB SG 0.0.0.0/0:80은 의도된 설계** — 3-3이 CloudShell에서 직접 curl로 403/200을 확인한다. prefix list로 좁히면 실패. 리뷰 규칙의 0.0.0.0/0 점검 항목에서 예외로 기록.
3. **커스텀 헤더 값 단일 소스**: CloudFront origin custom header와 listener rule이 같은 Terraform 참조를 쓰게 해 불일치 방지. mark.sh는 CloudFront 쪽 값을 읽어 ALB에 던진다.
4. `/v1/*` behavior에 POST 포함 전체 메서드 + CachingDisabled. 캐싱 정책을 빠뜨리면 POST가 CloudFront에서 막히거나 응답이 캐시된다.
5. Task Definition 이전에 Log Group이 존재해야 첫 태스크 로그 스트림(`book/skills-book-container/<id>`)이 생성된다 (6-1이 stream prefix `book` 존재를 검사 — awslogs-stream-prefix가 곧 스트림 prefix).
6. book 바이너리는 x86-64 → `runtime_platform X86_64` 누락 시(특히 ARM 로컬 빌드 습관) 태스크가 exec format error로 CrashLoop.
7. DynamoDB attribute 정의는 PK 하나만. 문제지의 Attributes 나열(client_id 등)을 AttributeDefinitions로 옮기면 validate 에러.
8. Alarm 검증 대기 최대 3분(채점 유의) — 경기 종료 전 4xx를 실제 발생시켜 ALARM 전환을 미리 확인해 둔다.
9. 채점 스크립트 fallback이 "VPC 내 ip 타입 TG 아무거나"를 잡으므로 실험용 TG를 남기지 말 것 (불필요 리소스 감점과도 연결).
10. CloudFront 배포 반영 5~10분 — 경기 후반 수정 금지 시간을 계산에 넣는다.

## 7. 검증 시드 (로컬 실측)

book 바이너리 로컬 실행 결과 (Metric Filter·API 검증 근거):

| 요청 | 응답 | 로그 status |
|---|---|---|
| `GET /health` | 200 | `status=200` |
| `GET /nope` (미정의 경로) | 404 | `status=404` → 4xx filter 매칭 |
| `POST /v1/book` (DDB 미연결) | 500 | `status=500` → 5xx filter 매칭 |

배포 후 검증 시나리오:

```bash
CF=https://$(terraform output -raw cloudfront_domain)
curl -I  $CF/                       # 200, index.html (default root object)
curl -I  $CF/main.jpeg              # 200
curl -s -X POST $CF/v1/book -H 'Content-Type: application/json' \
  -d '{"client_id":"t1","username":"tester","email":"t@ex.com","concert_name":"seed"}'   # booking_id 반환
aws dynamodb scan --table-name skills-book-booking --limit 5 --region ap-northeast-2      # 저장 확인
curl -s -o /dev/null -w '%{http_code}\n' http://<ALB_DNS>/health                          # 403
curl -s -o /dev/null -w '%{http_code}\n' -H "X-Origin-Verify: <값>" http://<ALB_DNS>/health  # 200
curl -s -o /dev/null -w '%{http_code}\n' https://<S3버킷>.s3.ap-northeast-2.amazonaws.com/index.html  # 403 (200 아님)
curl $CF/v1/nonexistent             # 404 유발 → 1~2분 내 skills-book-4xx-alarm ALARM 확인
```
