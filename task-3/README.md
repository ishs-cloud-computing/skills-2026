# task-3 — System operation

위에서 아래로 실행한다. 설계 근거는 [ARCHITECTURE.md](ARCHITECTURE.md).

> **대회 당일에는 [DAY-OF.md](../DAY-OF.md) 를 먼저 연다.** 과제지는 종이로 배부되어 파일 대조가 안 되므로,
> DAY-OF 8절 값 대조표로 종이 과제지를 훑고 다른 값에 형광펜을 친 뒤 이 런북으로 들어온다.

## 값 대조표

> [DAY-OF.md 8절 값 대조표](../DAY-OF.md#10-값-대조표) 로 이동했다.

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
c "$CF/images/no-such-object.jpg"                                            # 404 (403 아님)
c "$CF/images/"                                                              # 404 (버킷 목록 200 아님)

curl -s -o /dev/null -w "%{http_code} POST stress\n" -X POST "$CF/v1/stress?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'   # 201

c "$CF/v1/none?$Q"                                                           # 404
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                    # 403
c "$CF/v1/none?email=%27%20OR%201=1--&$Q"                                    # 404 (403 아님)
c "$CF/v1/user/../../etc/passwd?$Q"                                          # 403 아님

```

`scanner-ua` 룰은 이 시점엔 꺼져 있다(regex set 이 자리표시자뿐). 켜는 절차는 STEP 12.

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

### stress 부하 특성 실측 (부하 구간)

부하가 도는 동안 잰다. 유휴에는 아무것도 안 나온다.

```bash
# ── 리전 CloudShell ──
kubectl top pods | grep stress                                        # CPU (millicores)
expr $(kubectl logs deploy/stress --since=60s | grep -c '\[GIN\]') / 60   # rps
kubectl logs deploy/stress --since=60s | grep '\[GIN\]' | tail -20    # 요청당 서버 처리시간
```

요청당 millicore = CPU ÷ rps. 재구성 바이너리 기준값은 **1.2 millicore/req, 서버 처리시간
100~250µs** (`NOTES.md` 2026-08-24). 당일 값이 크게 다르면 HPA 목표치·`maxReplicas` 를
그 비율만큼 재검토한다 — CPU limit 은 쓰지 않는다(기각 근거는 NOTES.md).

- CloudWatch(us-east-1) → Logs Insights → `aws-waf-logs-skills-waf`
- WAF 콘솔(us-east-1) → sampled requests

### 스캐너 UA 차단 켜기 (콘솔, apply 불필요)

terraform 은 regex pattern set 두 개만 만든다. 룰은 콘솔에서 직접 넣는다.

**1) UA 목록 채우기** — WAF & Shield 콘솔 → **Regex pattern sets** → 리전 선택기 **Global (CloudFront)**
→ `skills-waf-scanner-uas` → Edit → **한 줄에 하나씩, 소문자로** (룰이 LOWERCASE 변환 후 매칭) → Save.
자리표시자 `__disabled__scanner__ua__` 줄은 지운다.

**2) 룰 추가** — 본 PC 에서 ARN 두 개를 뽑아 `waf/scanner-ua.json` 의 `<...>` 자리에 채운다.

```powershell
terraform output waf_api_paths_arn
terraform output waf_scanner_uas_arn
```

WAF 콘솔 → Web ACLs → `skills-waf` → Rules → **Add rules → Add my own rules → Rule builder →
JSON editor** → 채운 JSON 붙여넣기 → Add rule → Save.

되돌리려면 Web ACL 에서 `scanner-ua` 룰을 지운다.

검증 — 같은 UA 로 존재/비존재 경로를 각각 친다.

```bash
# ── 리전 CloudShell ──
curl -s -o /dev/null -w "%{http_code}\n" -A "gobuster/3.6" "$CF/v1/user?$Q"   # 403
curl -s -o /dev/null -w "%{http_code}\n" -A "gobuster/3.6" "$CF/dump.sql"     # 404
```

당일 변경 절차는 [ARCHITECTURE.md](ARCHITECTURE.md) "당일 변경 시나리오".

## STEP 99 — teardown

Ingress(ALB) → NodePool(Karpenter EC2) → 클러스터 → 스크립트가 만든 IAM·CFN → Terraform 순.
NodePool 을 클러스터보다 먼저 지워야 Karpenter 가 자기가 띄운 EC2 와 인스턴스 프로파일을 회수한다.

```bash
# ── 리전 CloudShell ──
kubectl delete -f k8s/20-ingress.yaml   # ALB 삭제까지 대기
kubectl delete -f k8s/01-nodepool.yaml -f k8s/00-nodeclass.yaml
kubectl get nodeclaims                  # 비워질 때까지 대기
```

```powershell
# ── 본 PC ──
eksctl delete cluster -f eksctl/cluster.yaml --disable-nodegroup-eviction
```

```bash
# ── 리전 CloudShell ── karpenter.sh · lbc.sh 가 만든 것 정리
bash scripts/teardown.sh
```

```powershell
# ── 본 PC ──
# ALB가 이미 없으므로 data.aws_lb 조회를 꺼야 plan 이 통과한다
terraform -chdir=terraform destroy -auto-approve -var alb_exists=false
```

S3 버킷에 객체가 남아 삭제가 막히면 `aws s3 rm s3://<bucket> --recursive` 후 재실행.

`Karpenter-<클러스터>` 스택이 `DELETE_FAILED` 로 남았으면 `bash scripts/teardown.sh` 를 그대로 실행하면 된다.
