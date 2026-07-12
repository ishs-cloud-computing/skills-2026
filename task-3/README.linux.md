# task-3 — System operation (Linux bash 버전)

[README.md](README.md)의 PowerShell 런북과 동일한 절차의 bash 판. 본 컴퓨터가 Linux/macOS이거나
전부 CloudShell에서 돌릴 때 사용한다. 설계 근거는 [ARCHITECTURE.md](ARCHITECTURE.md).

PowerShell 판과의 차이는 문법뿐이다.
- 값 읽기: `ConvertFrom-Json` → `jq`, placeholder 치환: `.Replace()` → `sed`.
- Linux엔 `aws`/`jq`/`sed`/`curl`이 있으므로 PowerShell이 우회했던 부분을 직접 쓴다.
- `curl`은 진짜 curl이다(`curl.exe` 불필요, `NUL` → `/dev/null`).

```
task-3/
├── terraform/   # VPC·RDS(+Proxy)·S3·ECR·ALB·CloudFront·WAF·노드 IAM
├── eksctl/      # Auto Mode 클러스터 (+ metrics-server, cloudwatch addon)
├── k8s/         # NodeClass/NodePool, 앱별 Deploy+Svc+TGB+HPA+PDB
├── db/          # DB 초기화 SQL + 런북 (STEP 7에서 진입 → db/README.linux.md)
└── app/         # Dockerfile (제공 바이너리를 당일 app/ 에 복사)
```

명령은 **두 곳**에서 실행한다. 각 블록 첫 줄 라벨을 보고 해당 위치에 붙여넣는다.
- **로컬 bash(본 컴퓨터)**: terraform·eksctl·kubectl 전부. tfstate가 여기 있다.
- **CloudShell(ap-northeast-2)**: 이미지 빌드/푸시만(STEP 4).

---

## STEP 0 — 사전 준비 (로컬 bash)

```bash
# ── 로컬 bash ──
cd task-3
# terraform/terraform.tfvars 수정: player_number, (필요시) db_password
# 리전·CIDR·앱 목록·DB 사양이 당일 과제와 다르면 terraform/locals.tf 한 파일만 수정

# 지급된 자격증명(환경변수로 주입). eksctl/kubectl도 이 값을 쓴다.
export AWS_ACCESS_KEY_ID='<ACCESS_KEY>'
export AWS_SECRET_ACCESS_KEY='<SECRET_KEY>'
export AWS_DEFAULT_REGION='ap-northeast-2'
export DB_PASSWORD='password'   # tfvars의 db_password와 동일하게
```

## STEP 1 — 선행 apply: 네트워크·노드롤·ECR (로컬 bash, ~3분)

eksctl가 참조할 VPC/서브넷과 이미지 push 대상 ECR을 먼저 만든다. 리프 리소스만 지정하면
VPC·서브넷·IGW·NAT·라우트·노드롤은 종속성으로 딸려 온다.

```bash
# ── 로컬 bash ──
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve \
  -target=data.aws_caller_identity.current \
  -target=aws_ecr_repository.app \
  -target=aws_vpc_endpoint.s3 \
  -target=aws_nat_gateway.this \
  -target=aws_route_table_association.public \
  -target=aws_route_table_association.private \
  -target=aws_iam_role_policy_attachment.node_minimal \
  -target=aws_iam_role_policy_attachment.node_ecr_pull
```

## STEP 2 — eksctl 클러스터 생성 (로컬 bash, ~15분)

서브넷·계정ID를 `terraform output`에서 읽어 `cluster.yaml`을 렌더한 뒤 생성한다.
이 터미널은 생성이 끝날 때까지 점유되므로, **바로 STEP 3을 새 터미널에서 병렬로** 돌린다.

```bash
# ── 로컬 bash ──
sn=($(terraform -chdir=terraform output -json private_subnet_ids | jq -r '.[]'))
acct=$(terraform -chdir=terraform output -raw account_id)

sed -e "s/subnet-REPLACE_A/${sn[0]}/" \
    -e "s/subnet-REPLACE_B/${sn[1]}/" \
    -e "s/ACCOUNT_ID/${acct}/" \
    eksctl/cluster.yaml > eksctl/cluster.rendered.yaml

eksctl create cluster -f eksctl/cluster.rendered.yaml   # kubeconfig 자동 병합
```

## STEP 3 — 전체 terraform apply (새 터미널, ~20분)

STEP 2와 병렬. **새 터미널이므로 STEP 0의 자격증명 4줄을 먼저 다시 실행**한 뒤:

```bash
# ── 로컬 bash (두 번째 터미널) ──
cd task-3
terraform -chdir=terraform apply -auto-approve
```

RDS Multi-AZ와 CloudFront 배포가 오래 걸린다. CloudFront 도메인은 배포 완료 전에 확정되므로
STEP 6에서 미리 제출할 수 있다.

## STEP 4 — 이미지 빌드/푸시 (CloudShell, 바이너리 수령 즉시)

PowerShell 판과 동일 — 이 스텝은 원래 CloudShell bash다. [README.md](README.md#step-4) STEP 4 그대로.

```bash
# ── CloudShell(ap-northeast-2) ──
#   git clone <repo> && cd task-3
#   제공 바이너리를 app/ 아래에 파일명 user·product·stress 로 복사.

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $REG

docker build --build-arg BINARY=user    -t $REG/user:v1    app/ && docker push $REG/user:v1
docker build --build-arg BINARY=product -t $REG/product:v1 app/ && docker push $REG/product:v1
docker build --build-arg BINARY=stress  -t $REG/stress:v1  app/ && docker push $REG/stress:v1
```

## STEP 5 — 클러스터 완료 후 노드풀 적용 (로컬 bash)

STEP 2 터미널에서 `eksctl create`가 끝난 것을 확인한 뒤:

```bash
# ── 로컬 bash ──
kubectl apply -f k8s/00-nodeclass.yaml -f k8s/01-nodepool.yaml
kubectl get nodeclass,nodepool   # Ready 확인
```

## STEP 6 — 엔드포인트 제출 (로컬 bash)

CloudFront 도메인은 EKS 준비와 무관하게 확정되므로 앱 배포 전에 미리 제출한다(조기 제출 = 채점 이득).

```bash
# ── 로컬 bash ──
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.

## STEP 7 — DB 초기화 (로컬 bash)

[db/README.linux.md](db/README.linux.md) 런북을 실행한다. 직결 엔드포인트 사용(프록시 X).

## STEP 8 — 앱 배포: placeholder 치환 후 apply (로컬 bash)

env는 각 앱 매니페스트에 직접 들어있다(공용 ConfigMap/Secret 없음). 앱마다 필요한 값이 달라
한 파일씩 명시적으로 치환+apply — 당일 한 앱만 바뀌어도 다른 앱에 번지지 않는다.

sed 구분자로 `#`를 쓴다(URL·ARN에 없음). DB_PASSWORD에 `#`가 들어있으면 구분자를 바꾼다.

```bash
# ── 로컬 bash ──
acct=$(terraform -chdir=terraform output -raw account_id)
REG="$acct.dkr.ecr.ap-northeast-2.amazonaws.com"   # 이미지는 STEP 4(CloudShell)에서 push됨
proxy=$(terraform -chdir=terraform output -raw db_proxy_endpoint)
dbport=$(terraform -chdir=terraform output -raw db_port)
bucket=$(terraform -chdir=terraform output -raw bucket_name)
tg_user=$(terraform    -chdir=terraform output -json tg_arns | jq -r '.user')
tg_product=$(terraform -chdir=terraform output -json tg_arns | jq -r '.product')
tg_stress=$(terraform  -chdir=terraform output -json tg_arns | jq -r '.stress')

# user (DB만)
sed -e "s#<ECR_URL>#$REG/user#" \
    -e "s#<TG_ARN>#$tg_user#" \
    -e "s#<PROXY_ENDPOINT>#$proxy#" \
    -e "s#<DB_PORT>#$dbport#" \
    -e "s#<DB_PASSWORD>#$DB_PASSWORD#" \
    k8s/10-user.yaml | kubectl apply -f -

# product (DB + S3)
sed -e "s#<ECR_URL>#$REG/product#" \
    -e "s#<TG_ARN>#$tg_product#" \
    -e "s#<PROXY_ENDPOINT>#$proxy#" \
    -e "s#<DB_PORT>#$dbport#" \
    -e "s#<DB_PASSWORD>#$DB_PASSWORD#" \
    -e "s#<BUCKET_NAME>#$bucket#" \
    k8s/11-product.yaml | kubectl apply -f -

# stress (env 없음 — 이미지·TG만)
sed -e "s#<ECR_URL>#$REG/stress#" \
    -e "s#<TG_ARN>#$tg_stress#" \
    k8s/12-stress.yaml | kubectl apply -f -

kubectl get pods -w   # Running 확인 (첫 파드가 노드 생성을 트리거, ~2분)
```

## STEP 9 — 검증 (로컬 bash)

```bash
# ── 로컬 bash ──
CF="https://$(terraform -chdir=terraform output -raw cloudfront_domain)"
Q="requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
c() { curl -s -o /dev/null -w "%{http_code} %{time_total}s $1\n" "$1"; }

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
tg_user=$(terraform -chdir=terraform output -json tg_arns | jq -r '.user')
aws elbv2 describe-target-health --target-group-arn "$tg_user"
```

## STEP 10 — 운영 (로컬 bash)

```bash
# ── 로컬 bash ──
kubectl top nodes; kubectl top pods; kubectl get hpa -w   # 스케일 동작 관찰
# CloudWatch → Container Insights / Logs Insights (앱 stdout 액세스 로그)
# WAF 콘솔(us-east-1) → sampled requests: SQLi·KnownBadInputs 룰 매치 확인
```

- 당일 특정 공격 패턴 추가 차단: `terraform/waf.tf`에 관리형 룰 블록을 하나 더 추가(ARCHITECTURE.md 참고)
- 당일 DB 엔진·API·인스턴스 타입 변경 절차: [ARCHITECTURE.md](ARCHITECTURE.md)의 "당일 변경 시나리오"
