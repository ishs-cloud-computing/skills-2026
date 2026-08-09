# task-3 — System operation

위에서 아래로 실행한다. 설계 근거는 [ARCHITECTURE.md](ARCHITECTURE.md).

## 실행 위치

| 위치 | 하는 일 | 준비 |
|---|---|---|
| 본 PC (PowerShell 7) | terraform, eksctl | `terraform.exe`·`eksctl.exe`·`aws.exe` PATH |
| VPC CloudShell | 이미지 빌드/푸시, DB 초기화 | 콘솔 `+` → Create VPC environment (VPC `skills-vpc` / private subnet / SG `skills-cloudshell-sg`) |
| 리전 CloudShell | kubectl, helm | CloudShell 열기 (ap-northeast-2) |

- VPC CloudShell 은 홈이 비영구다. 세션이 끊기면 파일이 사라진다.
- 파일은 본 PC 편집기에서 복사 → CloudShell 에서 `vim <파일>` 로 붙여넣어 저장한다.
- YAML 은 붙여넣기 전에 `:set paste`.

## 순서

번호순으로 하되, 아래 넷만 지키면 나머지는 병렬로 돌린다.

- **1a 끝나야** 2, 3 시작
- **1b 끝나야** 4 시작
- **2 끝나야** 5 시작 — 5 → 6 → 7 → 8 은 순서대로
- **8 의 ADDRESS 가 떠야** 9 시작

병렬로 돌릴 창:

| 창 | STEP |
|---|---|
| 본 PC 창1 | 1a → 1b |
| 본 PC 창2 | 2 |
| VPC CloudShell | 3 → 4 |
| 리전 CloudShell | 5 → 6 → 7 → 8 |

---

## STEP 0 — 사전 준비 (본 PC)

과제지와 대조해 값을 확인한다.

| 파일 | 값 |
|---|---|
| `terraform/terraform.tfvars` | `prefix`, `bucket_name`, `db_identifier`, `db_password` |
| `terraform/variables.tf` | `apps`, `image_tag` |
| `terraform/locals.tf` | 리전·CIDR·DB 사양, 개별 리소스 이름 |

`prefix` 를 바꿨으면 `eksctl/cluster.yaml`·`k8s/00-nodeclass.yaml`·`k8s/20-ingress.yaml`·`scripts/*.sh`·`README.md` 의 클러스터·ALB·프록시 이름도 같이 고친다.

```powershell
# ── 본 PC ──
cd task-3
aws login   # 또는 aws configure
```

## STEP 1a — 네트워크·ECR·S3 (본 PC, ~3분)

```powershell
# ── 본 PC ──
terraform -chdir=terraform init
$targets = @(
  "-target=aws_vpc_endpoint.s3"
  "-target=aws_nat_gateway.this"
  "-target=aws_route_table_association.public"
  "-target=aws_route_table_association.private"
  "-target=aws_ecr_repository.app"
  "-target=aws_s3_bucket.this"
  "-target=aws_security_group.cloudshell"
)

terraform -chdir=terraform apply -auto-approve @targets
terraform -chdir=terraform output -json private_subnet_ids   # subnet id 2개
```

output 이 나오면 새 창에서 STEP 2, CloudShell 에서 STEP 3 을 시작한다.

## STEP 1b — RDS + Proxy (본 PC 창1, ~15분)

```powershell
# ── 본 PC ──
terraform -chdir=terraform apply -auto-approve "-target=aws_db_proxy_target.this"

aws rds describe-db-proxy-targets --db-proxy-name skills-db-proxy --query "Targets[0].TargetHealth"
# {"State": "AVAILABLE"}
# UNAVAILABLE/AUTH_FAILURE 면 target 없이 terraform apply 재실행 후 1~2분 뒤 재확인
```

## STEP 2 — eksctl 클러스터 (본 PC 창2, ~20분)

```powershell
# ── 본 PC ──
cd task-3
terraform -chdir=terraform output -json private_subnet_ids
terraform -chdir=terraform output -json public_subnet_ids
```

`eksctl/cluster.yaml` 의 `subnet-REPLACE_*` 4곳을 위 값으로 바꾼다.

```powershell
# ── 본 PC ──
Select-String 'REPLACE' eksctl/cluster.yaml   # 출력 없어야 한다
eksctl create cluster -f eksctl/cluster.yaml
```

## STEP 3 — 이미지 빌드/푸시 (S3 콘솔 → VPC CloudShell)

1. S3 콘솔에서 STEP 1a 버킷에 `_bin/` 으로 바이너리 3개를 업로드한다.
2. VPC CloudShell 을 만든다. **private subnet** 을 고른다.

```bash
# ── VPC CloudShell ──
BUCKET=<bucket_name>
ACCT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCT.dkr.ecr.ap-northeast-2.amazonaws.com
TAG=v1                          # terraform image_tag 와 일치

aws s3 cp s3://$BUCKET/_bin/ . --recursive
chmod +x user product stress
file user product stress

aws ecr get-login-password | docker login --username AWS --password-stdin $REG
```

`app/Dockerfile` 을 참고해 앱마다 빌드하고 `$REG/<app>:$TAG` 로 push 한다. 베이스는 glibc 가 있는 `gcr.io/distroless/base-debian13`.

```bash
# ── VPC CloudShell ──
aws ecr describe-images --repository-name user --query 'imageDetails[].imageTags' --output text
aws s3 rm s3://$BUCKET/_bin/ --recursive
```

docker 가 안 되면 이미지 빌드만 리전 CloudShell 에서 한다.

## STEP 4 — DB 초기화 (VPC CloudShell)

과제지 스키마와 `db/01-schema.sql` 을 먼저 대조한다. dump 적재는 느리므로 탭을 하나 더 열어 STEP 5 이후와 겹쳐 돌린다.

```bash
# ── VPC CloudShell ──
DB=<db_endpoint>                # 프록시 아님, 직결
```

1. `vim 01-schema.sql` 에 `db/01-schema.sql` 을 붙여넣고 저장한 뒤:

   ```bash
   mysql -h $DB -u admin -p dev < 01-schema.sql
   ```

   여기까지 하면 STEP 5~8 을 먼저 진행해도 된다.

2. `vim load_user.dump` 에 dump 를 붙여넣고 저장한다. `wc -l load_user.dump` 로 원본과 줄 수를 대조한다.

   ```bash
   mysql -h $DB -u admin -p dev < load_user.dump
   ```

3. dump **뒤에** 인덱스를 만든다.

   ```bash
   mysql -h $DB -u admin -p dev -e 'ALTER TABLE user ADD INDEX idx_email (email);'
   ```

4. 검증 — `mysql -h $DB -u admin -p dev` 에서:

   ```sql
   SELECT COUNT(*) FROM user;   -- dump 건수
   SHOW INDEX FROM user;        -- idx_email
   ```

## STEP 5 — Karpenter (리전 CloudShell)

```bash
# ── 리전 CloudShell ──
aws eks update-kubeconfig --name skills-eks --region ap-northeast-2
kubectl get nodes    # Ready 1개

vim karpenter.sh     # scripts/karpenter.sh 붙여넣고 :wq
bash karpenter.sh    # ~3분
```

## STEP 6 — AWS Load Balancer Controller (리전 CloudShell)

```bash
# ── 리전 CloudShell ──
vim lbc.sh           # scripts/lbc.sh 붙여넣고 :wq
bash lbc.sh
kubectl get ingressclass alb
```

## STEP 7 — 노드풀 (리전 CloudShell)

```bash
# ── 리전 CloudShell ──
vim 00-nodeclass.yaml   # :set paste 후 붙여넣기
vim 01-nodepool.yaml

kubectl apply -f 00-nodeclass.yaml -f 01-nodepool.yaml
kubectl get ec2nodeclass,nodepool
```

## STEP 8 — 앱 + Ingress (리전 CloudShell)

본 PC 에서 값을 읽어 `k8s/1*.yaml` 의 placeholder 를 채운다.

```powershell
# ── 본 PC ──
terraform -chdir=terraform output -json ecr_image_uris
terraform -chdir=terraform output -raw db_proxy_endpoint
terraform -chdir=terraform output -raw db_port
terraform -chdir=terraform output -raw db_password
terraform -chdir=terraform output -raw bucket_name
```

| placeholder | 값 | 파일 |
|---|---|---|
| `<IMAGE>` | `ecr_image_uris.<app>` | 앱 3파일 |
| `<PROXY_ENDPOINT>` | `db_proxy_endpoint` | user, product |
| `<DB_PORT>` | `db_port` | user, product |
| `<DB_PASSWORD>` | `db_password` | user, product |
| `<BUCKET_NAME>` | `bucket_name` | product |

```bash
# ── 리전 CloudShell ──
vim 10-user.yaml     # :set paste 후 붙여넣기
vim 11-product.yaml
vim 12-stress.yaml
vim 20-ingress.yaml

grep -nE '^[^#]*<[A-Z_]+>' ./*.yaml    # 출력 없어야 한다

kubectl apply -f 10-user.yaml -f 11-product.yaml -f 12-stress.yaml -f 20-ingress.yaml
kubectl get pods -w
kubectl get ingress skills -w          # ADDRESS 에 ALB DNS (~3분)
```

ADDRESS 가 안 차면 `kubectl -n kube-system logs deploy/aws-load-balancer-controller`.

## STEP 9 — CloudFront + 엔드포인트 제출 (본 PC)

```powershell
# ── 본 PC ──
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 `https://<도메인>` 제출. 프로토콜 포함, 경로 금지.

## STEP 10 — 스모크 (리전 CloudShell)

```bash
# ── 리전 CloudShell ──
CF="https://<cloudfront_domain>"
Q="requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
c() { curl -s -o /dev/null -w "%{http_code} %{time_total}s $1\n" "$1"; }

curl -s -o /dev/null -w "%{http_code} POST user\n" -X POST "$CF/v1/user?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","username":"dbdump500001","email":"dbdump500001@example.org"}'   # 201
c "$CF/v1/user?email=dbdump500001@example.org&$Q"                            # 200

curl -s -o /dev/null -w "%{http_code} POST product\n" -X POST "$CF/v1/product?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","id":"dbdump500001","name":"dbdump500001","price":1234}'   # 201
c "$CF/v1/product?id=dbdump500001&$Q"                                        # 200

head -c 1024 /dev/zero > smoke.jpg
curl -s -o /dev/null -w "%{http_code} PUT product image\n" -X PUT "$CF/v1/product?$Q" \
  -F "requestid=999999999999" -F "uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729" \
  -F "id=dbdump500001" -F "image=@smoke.jpg"                                 # 200
c "$CF/images/dbdump500001.jpg"                                              # 200

curl -s -o /dev/null -w "%{http_code} POST stress\n" -X POST "$CF/v1/stress?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'   # 201

c "$CF/v1/none?$Q"                                                           # 404
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                    # 403
```

## STEP 11 — 유휴 1대 확인 (리전 CloudShell)

```bash
# ── 리전 CloudShell ──
kubectl get nodes                                                  # 1
kubectl -n kube-system get deploy karpenter                        # 1/1
kubectl -n kube-system get deploy aws-load-balancer-controller     # 1/1
kubectl get pods -A --field-selector status.phase=Pending          # 없어야 한다
kubectl get nodeclaims                                             # 0
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'length(Reservations[].Instances[])'                     # 1
```

1대에 안 들어가면 순서대로: `kubectl -n kube-system scale deploy/coredns --replicas=1` → 앱 requests 200m → `eksctl scale nodegroup` 으로 MNG 2대.

## STEP 12 — 운영 (리전 CloudShell + 콘솔)

```bash
# ── 리전 CloudShell ──
kubectl top nodes; kubectl top pods; kubectl get hpa -w
kubectl get nodeclaims -w
kubectl logs -f deploy/user
```

- CloudWatch(us-east-1) → Logs Insights → `aws-waf-logs-skills-waf`
- WAF 콘솔(us-east-1) → sampled requests

당일 변경 절차는 [ARCHITECTURE.md](ARCHITECTURE.md) "당일 변경 시나리오".
