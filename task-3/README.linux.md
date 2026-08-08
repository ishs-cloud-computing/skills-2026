# task-3 — System operation (Linux bash 버전)

[README.md](README.md)의 PowerShell 런북과 동일한 절차의 bash 판. 본 컴퓨터가 Linux/macOS이거나
전부 CloudShell에서 돌릴 때 사용한다. 설계 근거는 [ARCHITECTURE.md](ARCHITECTURE.md).

PowerShell 판과의 차이는 문법뿐이다.
- 값 읽기: `ConvertFrom-Json` → `jq`, placeholder 치환: `.Replace()` → `sed`.
- `curl`은 진짜 curl이다(`curl.exe` 불필요, `NUL` → `/dev/null`).

```
task-3/
├── terraform/   # VPC·ECR·RDS(+Proxy)·S3·CloudFront·WAF   (ALB는 여기 없다)
├── eksctl/      # 클러스터 + Karpenter + MNG 1대 + addon
├── k8s/         # EC2NodeClass/NodePool, 앱별 Deploy+Svc+HPA, Ingress(ALB 전체)
├── db/          # DB 초기화 SQL (STEP 8에서 사용)
└── app/         # Dockerfile (제공 바이너리를 당일 app/ 에 복사)
```

명령은 **두 곳**에서 실행한다. 각 블록 첫 줄 라벨을 보고 해당 위치에 붙여넣는다.
- **로컬 bash(본 컴퓨터)**: terraform·eksctl·helm·kubectl 전부. tfstate가 여기 있다.
- **CloudShell(ap-northeast-2)**: 이미지 빌드/푸시(STEP 3)와 DB 초기화(STEP 8).

**ALB는 Terraform이 아니라 Ingress가 만든다.** 그래서 CloudFront(=제출 엔드포인트)는 STEP 6 이후에야 생성 가능하다.

---

## STEP 0 — 사전 준비 (로컬 bash)

당일 과제지와 대조해 먼저 아래 파일을 손본다.

| 파일 | 확인할 값 |
|---|---|
| `terraform/terraform.tfvars` | `bucket_name`(전역 유일), `db_password` |
| `terraform/variables.tf` | `apps`(앱 목록), `image_tag` |
| `terraform/locals.tf` | 리전·CIDR·DB 사양, `cluster_name`, `alb_name` |

`db_password`를 적는 곳은 tfvars 한 곳뿐이다. 앱 매니페스트에 넣을 값은 STEP 6에서 `terraform output`으로 읽으므로 셸 환경변수를 따로 맞출 필요가 없다.
`cluster_name`·`alb_name`·앱 목록을 바꿀 때 함께 고쳐야 하는 짝은 [ARCHITECTURE.md](ARCHITECTURE.md)의 "파일 간 결합" 표에 있다.

```bash
# ── 로컬 bash ──
cd task-3
aws configure   # 지급 키 입력, region: ap-northeast-2, output: json
```

## STEP 1 — 선행 apply: 네트워크·ECR·S3·RDS (로컬 bash, ~15분)

CloudFront·WAF·S3 정책은 ALB가 생겨야 하므로 STEP 7로 미룬다.

```bash
# ── 로컬 bash ──
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve \
  -target=aws_vpc_endpoint.s3 \
  -target=aws_nat_gateway.this \
  -target=aws_route_table_association.public \
  -target=aws_route_table_association.private \
  -target=aws_ecr_repository.app \
  -target=aws_s3_bucket.this \
  -target=aws_db_proxy_target.this
```

RDS Multi-AZ가 오래 걸린다. **끝나기를 기다리지 말고 STEP 2를 새 터미널에서 시작**한다.

## STEP 2 — eksctl 클러스터 생성 (새 터미널, ~20분)

```bash
# ── 로컬 bash (두 번째 터미널) ──
cd task-3
PRV=($(terraform -chdir=terraform output -json private_subnet_ids | jq -r '.[]'))
PUB=($(terraform -chdir=terraform output -json public_subnet_ids  | jq -r '.[]'))

sed -e "s/subnet-REPLACE_PRIVATE_A/${PRV[0]}/" -e "s/subnet-REPLACE_PRIVATE_B/${PRV[1]}/" \
    -e "s/subnet-REPLACE_PUBLIC_A/${PUB[0]}/"  -e "s/subnet-REPLACE_PUBLIC_B/${PUB[1]}/" \
    eksctl/cluster.yaml > eksctl/cluster.rendered.yaml

eksctl create cluster -f eksctl/cluster.rendered.yaml   # kubeconfig 자동 병합
```

> **`karpenter.version`이 실패하면**: eksctl은 상한이 아니라 하한(0.28.0)만 검사하므로 거절은 대개 그 버전의 Helm 차트가 없다는 뜻이다. 호환성 매트릭스에서 실재하는 stable로 내린다(k8s 1.36은 Karpenter >= 1.13). 그래도 안 되면 `karpenter:` 블록을 지우고 클러스터만 만든 뒤 [공식 Getting Started](https://karpenter.sh/docs/getting-started/)의 Helm 절차로 직접 설치한다.

## STEP 3 — 이미지 빌드/푸시 (CloudShell)

[README.md](README.md#step-3--이미지-빌드푸시-cloudshell-바이너리-수령-즉시)의 STEP 3(3a~3d)과 동일하다 — 원래 bash 블록이라 문법 차이가 없다.

## STEP 4 — 컨트롤러 정리 + LBC 설치 (로컬 bash)

STEP 2의 `eksctl create`가 끝난 뒤. **Karpenter 축소를 NodePool(STEP 5)보다 먼저** 실행한다 — 순서를 뒤집으면 Karpenter가 자기 자신의 Pending replica를 위해 노드를 1대 더 띄운다. (근거: [ARCHITECTURE.md](ARCHITECTURE.md)의 "유휴 EC2 = 1대")

```bash
# ── 로컬 bash ──
kubectl -n karpenter scale deploy/karpenter --replicas=1

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=skills-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set replicaCount=1

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
kubectl get ingressclass alb   # 차트가 만든다. 없으면 Ingress가 무시된다
```

ServiceAccount와 IAM 역할은 eksctl이 이미 만들었다(`wellKnownPolicies`) — 정책 JSON을 받아 `aws iam create-policy` 할 필요가 없다.

## STEP 5 — 노드풀 적용 (로컬 bash)

```bash
# ── 로컬 bash ──
kubectl apply -f k8s/00-nodeclass.yaml -f k8s/01-nodepool.yaml
kubectl get ec2nodeclass,nodepool   # Ready 확인
```

## STEP 6 — 앱 + Ingress 배포 (로컬 bash)

env는 각 앱 매니페스트에 직접 들어있다. 치환 후 apply하고, 마지막에 Ingress를 올린다 — 이 Ingress가 LBC에게 ALB를 만들게 하는 방아쇠다.

```bash
# ── 로컬 bash ──
IMG=$(terraform -chdir=terraform output -json ecr_image_uris)
PROXY=$(terraform -chdir=terraform output -raw db_proxy_endpoint)
DBPORT=$(terraform -chdir=terraform output -raw db_port)
DBPW=$(terraform -chdir=terraform output -raw db_password)
BUCKET=$(terraform -chdir=terraform output -raw bucket_name)

for a in user product stress; do
  sed -e "s|<IMAGE>|$(echo "$IMG" | jq -r ".$a")|" \
      -e "s|<PROXY_ENDPOINT>|$PROXY|" \
      -e "s|<DB_PORT>|$DBPORT|" \
      -e "s|<DB_PASSWORD>|$DBPW|" \
      -e "s|<BUCKET_NAME>|$BUCKET|" \
      k8s/1?-$a.yaml | kubectl apply -f -
done

# Ingress (치환할 값 없음)
kubectl apply -f k8s/20-ingress.yaml

kubectl get pods -w                       # Running 확인
kubectl get ingress skills -w             # ADDRESS에 ALB DNS가 뜰 때까지 (~3분)
```

ADDRESS가 비어 있으면 `kubectl -n kube-system logs deploy/aws-load-balancer-controller`로 원인을 본다. 흔한 원인은 퍼블릭 서브넷의 `kubernetes.io/role/elb` 태그 누락(terraform `vpc.tf`)이다.

## STEP 7 — CloudFront 생성 + 엔드포인트 제출 (로컬 bash)

Ingress의 ADDRESS가 뜬 뒤 실행한다. `data "aws_lb"`가 그 ALB를 조회해 origin에 건다.

```bash
# ── 로컬 bash ──
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.

## STEP 8 — DB 초기화 (RDS 콘솔 → CloudShell)

[README.md](README.md#step-8--db-초기화-rds-콘솔--cloudshell)의 STEP 8과 동일하다 — 전 과정을 브라우저 CloudShell에서 수행하므로 로컬 OS와 무관하다.

## STEP 9 — 검증 (로컬 bash)

```bash
# ── 로컬 bash ──
CF="https://$(terraform -chdir=terraform output -raw cloudfront_domain)"
Q="requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
c() { curl -s -o /dev/null -w "%{http_code} %{time_total}s $1\n" "$1"; }

curl -s -o /dev/null -w '%{http_code} POST user\n' -X POST "$CF/v1/user?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","username":"dbdump500001","email":"dbdump500001@example.org"}'  # 201
c "$CF/v1/user?email=dbdump500001@example.org&$Q"                          # 200

curl -s -o /dev/null -w '%{http_code} POST product\n' -X POST "$CF/v1/product?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","id":"dbdump500001","name":"dbdump500001","price":1234}'  # 201
c "$CF/v1/product?id=dbdump500001&$Q"                                      # 200

head -c 1024 /dev/urandom > /tmp/smoke.jpg
curl -s -o /dev/null -w '%{http_code} PUT product image\n' -X PUT "$CF/v1/product?$Q" \
  -F "requestid=999999999999" -F "uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729" \
  -F "id=dbdump500001" -F "image=@/tmp/smoke.jpg"                          # 200
c "$CF/images/dbdump500001.jpg"                                           # 200

curl -s -o /dev/null -w '%{http_code} POST stress\n' -X POST "$CF/v1/stress?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'  # 201

c "$CF/v1/none?$Q"                                                         # 404 (Ingress fixed-response)
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                  # 403 (WAF SQLi)
```

## STEP 10 — 유휴 1대 확인 (로컬 bash)

**비용 ratio의 전제**다. 트래픽이 없을 때 running EC2가 1대여야 한다.

```bash
# ── 로컬 bash ──
kubectl get nodes                                                  # 1개
kubectl -n karpenter get deploy karpenter                          # 1/1
kubectl -n kube-system get deploy aws-load-balancer-controller     # 1/1
kubectl get pods -A --field-selector status.phase=Pending          # 비어 있어야 한다
kubectl get nodeclaims                                             # 유휴 시 0개
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'length(Reservations[].Instances[])'                     # 1
```

Pending 파드가 하나라도 남아 있으면 Karpenter가 노드를 띄워 1대가 깨진다.
노드 1대에 안 들어가면 조정 순서는 ① `kubectl -n kube-system scale deploy/coredns --replicas=1`
→ ② 앱 requests 200m로 → ③ MNG를 2대로 (`eksctl scale nodegroup`).

## STEP 11 — 운영 (로컬 bash)

```bash
# ── 로컬 bash ──
kubectl top nodes; kubectl top pods; kubectl get hpa -w   # 스케일 동작 관찰
kubectl get nodeclaims -w                                 # Karpenter 노드 증감
```

콘솔에서 볼 것:
- CloudWatch → Logs Insights: WAF 로그 쿼리 세트는 `queries/` (앱 stdout은 `kubectl logs`)
- WAF 콘솔(us-east-1) → sampled requests: SQLi·KnownBadInputs 룰 매치 확인

당일 변경 절차는 [ARCHITECTURE.md](ARCHITECTURE.md)의 "당일 변경 시나리오"를 따른다.
