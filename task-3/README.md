# task-3 — System operation

CloudFront(단일 엔드포인트) → 내부 ALB(VPC Origin) → EKS Auto Mode(t3.medium) 위 user/product/stress + RDS(Proxy) + S3 이미지. **T+60분 트래픽 시작 전 완료가 목표** — 아래를 위에서 아래로 실행한다. 설계 근거·당일 변경 절차·인스턴스 타입별 튜닝은 [ARCHITECTURE.md](ARCHITECTURE.md).

```
task-3/
├── terraform/   # VPC·RDS(+Proxy)·S3·ECR·ALB·CloudFront·WAF·노드 IAM
├── eksctl/      # Auto Mode 클러스터 (+ metrics-server, cloudwatch addon)
├── k8s/         # NodeClass/NodePool, DB config, 앱별 Deploy+Svc+TGB+HPA+PDB
├── db/          # DB 초기화 SQL + 런북 (7번에서 진입)
└── app/         # Dockerfile (제공 바이너리를 당일 app/ 에 복사)
```

## 0. 사전 준비

```bash
cd task-3
# terraform/terraform.tfvars 수정: player_number, (필요시) db_password
# 리전·CIDR·앱 목록·DB 사양이 당일 과제와 다르면 terraform/locals.tf 한 파일만 수정
export DB_PASSWORD='password'   # tfvars의 db_password와 동일하게
```

## 1. [T+0] 선행 apply — VPC·노드롤·ECR (~3분)

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve \
  -target=aws_vpc.this -target=aws_subnet.public -target=aws_subnet.private \
  -target=aws_internet_gateway.this -target=aws_nat_gateway.this \
  -target=aws_route_table.public -target=aws_route_table.private \
  -target=aws_route_table_association.public -target=aws_route_table_association.private \
  -target=aws_vpc_endpoint.s3 \
  -target=aws_iam_role.automode_node \
  -target=aws_iam_role_policy_attachment.node_minimal \
  -target=aws_iam_role_policy_attachment.node_ecr_pull \
  -target=aws_ecr_repository.app
```

## 2. [T+3] eksctl 클러스터 생성 — 백그라운드 (~15분)

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SUBNET_A=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=private-subnet-1 --query 'Subnets[0].SubnetId' --output text)
SUBNET_B=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=private-subnet-2 --query 'Subnets[0].SubnetId' --output text)
sed -e "s|subnet-REPLACE_A|$SUBNET_A|" -e "s|subnet-REPLACE_B|$SUBNET_B|" \
    -e "s|ACCOUNT_ID|$ACCOUNT_ID|" eksctl/cluster.yaml > eksctl/cluster.rendered.yaml
nohup eksctl create cluster -f eksctl/cluster.rendered.yaml > /tmp/eksctl.log 2>&1 &
```

## 3. [T+3] 전체 terraform apply — eksctl과 병렬 (~20분)

RDS Multi-AZ와 CloudFront VPC Origin이 오래 걸린다. 그대로 두고 4번 진행.

```bash
terraform -chdir=terraform apply -auto-approve
```

## 4. [T+5~] 바이너리 수령 즉시 이미지 빌드/푸시 — AWS CloudShell(ap-northeast-2)

RDS가 private subnet에 있어 워크스테이션에서 사설망 리소스에 닿지 않고 로컬에 Docker가
없을 수 있으므로, Docker·인터넷·ECR 접근이 모두 되는 **CloudShell**에서 in-region으로
빌드/푸시한다. 콘솔 우상단 리전이 **ap-northeast-2**인지 확인하고 CloudShell을 연다.
(CloudShell은 2024-09부터 전 상용 리전에서 Docker를 내장한다.)

```bash
# CloudShell에 app/(Dockerfile) + 제공 바이너리(user/product/stress)를 올린다:
#   git clone <repo> && cd task-3   (또는 Actions → Upload file 로 app/ 업로드)
# 제공 바이너리는 app/ 아래에 파일명 user·product·stress 로 복사.

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $REG
# CloudShell=x86_64 → 제공 바이너리(x86 AL2023 빌드)와 동일 아키텍처. buildkit provenance
# 매니페스트를 피하려 buildx 대신 classic build+push 사용.
# 앱별로 한 줄씩 명시 — 당일 특정 앱만 빌드가 달라지면 그 줄(또는 app/Dockerfile 사본)만 고친다.
docker build --build-arg BINARY=user    -t $REG/skills-user:v1    app/ && docker push $REG/skills-user:v1
docker build --build-arg BINARY=product -t $REG/skills-product:v1 app/ && docker push $REG/skills-product:v1
docker build --build-arg BINARY=stress  -t $REG/skills-stress:v1  app/ && docker push $REG/skills-stress:v1
```

## 5. [T+20] 클러스터 완료 후 노드풀 적용

`tail -f /tmp/eksctl.log`로 완료 확인 후:

```bash
kubectl apply -f k8s/00-nodeclass.yaml -f k8s/01-nodepool.yaml
kubectl get nodeclass,nodepool   # Ready 확인
```

## 6. [T+23] 엔드포인트 제출

3번 apply 완료 후 (미완이면 `terraform state show`로 미리 확인 가능):

```bash
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.

## 7. [T+25] DB 초기화 — [db/README.md](db/README.md) 런북 실행

직결 엔드포인트 사용(프록시 X). 스키마 → dump 적재 → email 인덱스 → admin native 전환 → 검증 순.

## 8. [T+30] 앱 배포 — placeholder 치환 후 apply

env는 각 앱 매니페스트에 직접 들어있다(공용 ConfigMap/Secret 없음). 앱마다 필요한 값이
달라 한 파일씩 명시적으로 sed+apply — 당일 한 앱만 바뀌어도 다른 앱에 번지지 않는다.

```bash
REG=$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com   # 이미지는 CloudShell(4번)에서 push, 배포는 여기서
PROXY=$(terraform -chdir=terraform output -raw db_proxy_endpoint)
DB_PORT=$(terraform -chdir=terraform output -raw db_port)
BUCKET=$(terraform -chdir=terraform output -raw bucket_name)
TG=$(terraform -chdir=terraform output -json tg_arns)

# user (DB만)
sed -e "s|<ECR_URL>|$REG/skills-user|" -e "s|<TG_ARN>|$(echo $TG|jq -r .user)|" \
    -e "s|<PROXY_ENDPOINT>|$PROXY|" -e "s|<DB_PORT>|$DB_PORT|" -e "s|<DB_PASSWORD>|$DB_PASSWORD|" \
    k8s/10-user.yaml | kubectl apply -f -

# product (DB + S3)
sed -e "s|<ECR_URL>|$REG/skills-product|" -e "s|<TG_ARN>|$(echo $TG|jq -r .product)|" \
    -e "s|<PROXY_ENDPOINT>|$PROXY|" -e "s|<DB_PORT>|$DB_PORT|" -e "s|<DB_PASSWORD>|$DB_PASSWORD|" \
    -e "s|<BUCKET_NAME>|$BUCKET|" \
    k8s/11-product.yaml | kubectl apply -f -

# stress (env 없음 — 이미지·TG만)
sed -e "s|<ECR_URL>|$REG/skills-stress|" -e "s|<TG_ARN>|$(echo $TG|jq -r .stress)|" \
    k8s/12-stress.yaml | kubectl apply -f -

kubectl get pods -w   # Running 확인 (첫 파드가 노드 생성을 트리거, ~2분)
```

## 9. [T+35] 검증

```bash
CF=https://$(terraform -chdir=terraform output -raw cloudfront_domain)
Q="requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
c() { curl -s -o /dev/null -w "%{http_code} %{time_total}s $1\n" "$@"; }

c "$CF/v1/user?email=dbdump500001@example.org&$Q"                          # 200
c "$CF/v1/product?id=dbdump500001&$Q"                                      # 200
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$CF/v1/stress?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'  # 201
c "$CF/v1/none?$Q"                                                         # 404
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                  # 403 (WAF SQLi)
c "$CF/images/product50001.jpg"                                            # 200 (이미지 업로드 후)

# 타깃 등록 상태
kubectl get targetgroupbindings
aws elbv2 describe-target-health --target-group-arn $(terraform -chdir=terraform output -json tg_arns | jq -r .user)
```

## 10. [T+40~] 운영

```bash
kubectl top nodes; kubectl top pods; kubectl get hpa -w   # 스케일 동작 관찰
# CloudWatch → Container Insights / Logs Insights (앱 stdout 액세스 로그)
# WAF 콘솔(us-east-1) → sampled requests: 룰별 매치 확인
```

- 실트래픽 /v1/* 요청에 requestid·uuid 쿼리스트링이 항상 있으면 누락-차단 룰 활성:
  `terraform -chdir=terraform apply -auto-approve -var waf_v1_block_enabled=true` (~1분)
- CommonRuleSet에서 정상 트래픽 매치가 없는 룰만 개별 block 전환 (ARCHITECTURE.md 참고)
- 당일 DB 엔진·API·인스턴스 타입 변경 절차: [ARCHITECTURE.md](ARCHITECTURE.md)의 "당일 변경 시나리오"
