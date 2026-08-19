# set-08 / task-1 — Solution Architecture

CloudFront 단일 엔드포인트로 S3 정적 페이지 + ECS Fargate Book API(`/v1/*`)를 제공. 설계 근거·함정은 [plan.md](plan.md) 참고.

```
set-08/task-1/
├── terraform/   # 전체 인프라 (VPC → S3/CloudFront → ALB → ECR/ECS → DDB/KMS → CloudWatch)
├── app/         # Dockerfile (빌드 컨텍스트는 shared/provided/task-1)
├── plan.md      # 설계 문서
└── task.md · mark.md · mark.sh
```

## Quick Start

```bash
cd set-08/task-1/terraform

# 0. 비번호 주입
sed -i 's/bibunho = "00"/bibunho = "<비번호>"/' terraform.tfvars

# 1. ECR 먼저 생성 (Service가 이미지 없이는 안정화 안 됨)
terraform init
terraform apply -target=aws_ecr_repository.book

# 2. 이미지 빌드·푸시 (x86_64)
ECR_URL=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker build --platform linux/amd64 -f ../app/Dockerfile -t "${ECR_URL}:v1" ../../../shared/provided/task-1
docker push "${ECR_URL}:v1"

# 3. 전체 apply (CloudFront 배포 5~10분 소요)
terraform apply

# 4. 안정화 확인
aws ecs wait services-stable --cluster skills-book-cluster --services skills-book-service --region ap-northeast-2
CF=$(terraform output -raw cloudfront_domain_name)
curl -I "https://${CF}/"            # 200
curl -I "https://${CF}/main.jpeg"   # 200
curl -s -X POST "https://${CF}/v1/book" -H 'Content-Type: application/json' \
  -d '{"client_id":"t1","username":"tester","email":"t@ex.com","concert_name":"seed"}'   # booking_id 반환

# 5. ALB 헤더 차단 확인
ALB=$(terraform output -raw alb_dns_name)
HDR=$(terraform output -raw origin_verify_value)
curl -s -o /dev/null -w '%{http_code}\n' "http://${ALB}/health"                             # 403
curl -s -o /dev/null -w '%{http_code}\n' -H "X-Origin-Verify: ${HDR}" "http://${ALB}/health" # 200

# 6. 4xx 알람 시드 (1~2분 내 skills-book-4xx-alarm ALARM 전환 확인)
curl -s -o /dev/null "https://${CF}/v1/nonexistent"
aws cloudwatch describe-alarms --alarm-names skills-book-4xx-alarm --region ap-northeast-2 \
  --query 'MetricAlarms[].StateValue' --output text

# 7. 셀프 채점 (CloudShell에서 실행 — 실제 채점 환경과 동일하게 검증)
#    AWS Console → CloudShell 실행 → 파일 업로드로 mark.sh 전송 (또는 git clone) 후:
BIBUNHO=<비번호> bash mark.sh
```

> 채점은 CloudShell에서 CloudShell을 실행한 IAM User/Role 권한으로 진행된다 (task.md 50, mark.md 8·13). 별도 Access Key를 발급하지 않으므로, 로컬 AWS CLI 프로파일에서만 통과하고 CloudShell 기본 권한으로는 막히는 조회가 없는지 미리 CloudShell에서 `mark.sh`를 한 번 실행해 확인해 둔다. `mark.sh`는 `terraform output`에 의존하지 않고 태그/이름으로 리소스를 조회하도록 작성되어 있어 로컬 state 없이도 동일하게 동작한다.

## 정리

```bash
terraform -chdir=set-08/task-1/terraform destroy   # 저장소 루트 기준
```
