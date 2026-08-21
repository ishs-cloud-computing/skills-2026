# set-09 / task-1 — Solution Architecture

CloudFront 단일 엔드포인트로 S3 정적 페이지 + ECS Fargate Book API(`/v1/*`, `/health`)를 제공하는 콘서트 예약 서비스. 모든 리소스명은 `<비번호>-` prefix 고정.

```
set-09/task-1/
├── terraform/   # 전체 인프라 (VPC → S3/CloudFront → ALB → ECR/ECS → DynamoDB → CloudWatch)
├── app/         # Dockerfile (빌드 컨텍스트는 shared/provided/task-1)
└── task.md · mark.md · mark.sh
```

## Quick Start

```bash
cd set-09/task-1/terraform

# 0. 비번호 주입
sed -i 's/player_number = "00"/player_number = "<비번호>"/' terraform.tfvars

# 1. ECR 먼저 생성 (Service가 이미지 없이는 안정화 안 됨)
terraform init
terraform apply -target=aws_ecr_repository.book

# 2. 이미지 빌드·푸시 (latest 태그, x86_64 고정)
ECR_URL=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker build --platform linux/amd64 -f ../app/Dockerfile -t "${ECR_URL}:latest" ../../../shared/provided/task-1
docker push "${ECR_URL}:latest"

# 3. 전체 apply (CloudFront 배포 5~10분 소요)
terraform apply

# 4. 안정화·검증 (mark.sh 채점 경로와 동일)
aws ecs wait services-stable --cluster <비번호>-book-cluster --services <비번호>-book-service --region ap-northeast-2
CF=$(terraform output -raw cloudfront_domain_name)
curl -s -o /dev/null -w '%{http_code}\n' "https://${CF}/"          # 200
curl -s -o /dev/null -w '%{http_code}\n' "https://${CF}/main.jpeg" # 200
curl -s -o /dev/null -w '%{http_code}\n' "https://${CF}/health"    # 200
curl -s -X POST "https://${CF}/v1/book" -H 'Content-Type: application/json' \
  -d '{"client_id":"t1","username":"tester","email":"t@ex.com","concert_name":"Seoul2026"}'   # booking_id 반환
aws dynamodb get-item --table-name <비번호>-booking-table \
  --key '{"client_id":{"S":"t1"}}' --region ap-northeast-2         # 6개 속성 확인

# 5. ALB 직접 접근 차단 확인 (CloudFront 경유만 허용)
ALB=$(terraform output -raw alb_dns_name)
HDR=$(terraform output -raw origin_verify_value)
curl -s -o /dev/null -w '%{http_code}\n' "http://${ALB}/health"                              # 403
curl -s -o /dev/null -w '%{http_code}\n' -H "X-Origin-Verify: ${HDR}" "http://${ALB}/health" # 200

# 6. 셀프 채점 (CloudShell에서 실행 — 실제 채점 환경과 동일하게 검증)
#    AWS Console → CloudShell → 파일 업로드로 mark.sh 전송 (또는 git clone) 후:
bash mark.sh <비번호>
```

> - 채점은 CloudShell IAM User(Role) 권한으로 진행된다 (mark.md 2·3). `mark.sh`는 이름/태그로 리소스를 조회하므로 로컬 state 없이 동작한다.
> - `latest` 태그 이미지를 재푸시한 경우 Terraform은 diff를 못 보므로 `aws ecs update-service --cluster <비번호>-book-cluster --service <비번호>-book-service --force-new-deployment`로 재배포한다.
> - 버킷명 `<비번호>-static-site`는 글로벌 유니크 — 대회 당일 충돌로 생성 실패 시 심사위원에게 문의한다.

## 정리

```bash
terraform -chdir=set-09/task-1/terraform destroy   # CloudFront 비활성화+삭제로 수 분 소요 (저장소 루트 기준)
```

## 요구사항 ↔ 채점 ↔ 구현 매핑

| 채점 항목 | 요구사항 (task.md) | 구현 |
|---|---|---|
| 1-1 VPC/Subnet | 3장: 10.0.0.0/16, public-subnet 2개(2a/2c) | `vpc.tf` — `aws_vpc.this`, `aws_subnet.public` (Name 태그 `<비번호>-public-subnet-N`) |
| 1-2 IGW/라우팅 | 3장: IGW Attach, 0.0.0.0/0→IGW | `vpc.tf` — `aws_internet_gateway`, `aws_route.public_internet` |
| 1-3 명명 규칙 | 유의사항 19·22 | 모든 리소스 `local.*_name` = `<비번호>-` prefix (`variables.tf` locals) |
| 2-1 S3 업로드 | 4장: index.html·main.jpeg | `s3.tf` — `aws_s3_object.index/main_image` (content_type 명시) |
| 2-2 퍼블릭 차단 | 4장: OAC + 직접 접근 금지 | `s3.tf` — PAB 전체 true + OAC 버킷 정책 |
| 2-3 CF 접근/상태 | 5장: Default Root Object, S3 오리진 | `cloudfront.tf` — default behavior→S3, `default_root_object` |
| 3-1 ECR | 6장: `<비번호>-book-ecr` | `ecr.tf` |
| 3-2 latest/AMD64 | 6장: latest 태그, Linux/AMD64 | 런북 2단계 push + `ecs.tf` `runtime_platform X86_64` |
| 4-1 Cluster/Task | 7.1·7.4: ACTIVE, Running ≥1 | `ecs.tf` — cluster + service (desired 2) |
| 4-2 Task Definition | 7.2: 8080, CPU 256/MEM 512 | `ecs.tf` — task definition (`task_cpu/task_memory` 변수) |
| 4-3 환경 변수 | 7.2: AWS_REGION, TABLE_NAME | `ecs.tf` — environment (region·table locals 단일 소스) |
| 4-4 IAM Role | 7.3: Exec + Task Role(DDB 저장) | `iam.tf` — managed ExecutionRolePolicy + PutItem 최소 권한 |
| 4-5 /health 200 | 5장: /health→ALB 오리진 | `cloudfront.tf` — `/health` ordered behavior (CachingDisabled) |
| 5-1 ALB | 8장: internet-facing | `alb.tf` — `aws_lb.this` |
| 5-2 Listener/TG | 8장: HTTP:80, TG HTTP:8080 IP, /health 200 | `alb.tf` — listener + `aws_lb_target_group.app` |
| 5-3 보안그룹 | 8장 표: alb-sg 80/0.0.0.0/0, ecs-sg 8080/alb-sg | `alb.tf` `aws_security_group.alb` + `ecs.tf` `aws_security_group.ecs` (소스 SG 단일) |
| 6-1 테이블 | 9장: client_id PK(S) | `dynamodb.tf` — PAY_PER_REQUEST |
| 6-2·6-3 저장/스키마 | 9·11장: POST /v1/book → 6속성 | 앱 동작 (env + PutItem 권한 + CF `/v1/*` behavior가 전제) |
| 7-1 로그 그룹 | 유의사항 18: `/skillskorea/ecs/app` | `cloudwatch.tf` (prefix 예외 고정값) |
| 7-2 스트림/수집 | 10장: `ecs/<컨테이너>/<TaskID>` | `ecs.tf` — `awslogs-stream-prefix = "ecs"` |
| 7-3 awslogs 설정 | 10장 옵션 표 | `ecs.tf` — logConfiguration |
| 8-1 종합 연계 | 5·11장 | CF 단일 엔드포인트 (위 전체) |
| 8-2 불필요 리소스 | 유의사항 12 | NAT/EIP/Endpoint/KMS/알람 미생성, ALB 1개·EC2 0대 |

### 설계 메모

- **Public-only 토폴로지**: 과제가 Private Subnet·NAT를 요구하지 않고 ECS Task를 Public Subnet + Public IP로 명시(7.4). NAT 미생성으로 비용·8-2 감점 리스크 제거. ECR pull·DDB·Logs는 Public IP로 나간다.
- **origin-verify 헤더**: 과제 8장 "사용자는 ALB DNS를 직접 호출하지 않는다"를 CloudFront custom header + ALB 리스너(기본 403, 헤더 일치 시만 forward)로 강제. TG 헬스체크는 리스너를 거치지 않으므로 영향 없음.
- **`/health` behavior 캐시 금지**: 캐시되면 Task가 죽어도 200이 반환돼 장애가 가려지고, 반대로 오류가 캐시되면 채점 4-5가 실패한다.
- **latest 2단계 배포**: 이미지 push 전 전체 apply 시 Task가 `CannotPullContainerError`로 크래시 루프 — 런북 순서(ECR targeted apply → push → 전체 apply)를 지킨다.
- **바뀌기 쉬운 축 변수화**: 비번호·리전·AZ·CIDR·포트·CPU/MEM·태그·로그 그룹명 전부 `variables.tf` — 당일 30% 변경 대응.
