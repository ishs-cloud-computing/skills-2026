# task-3 — System operation

CloudFront(단일 엔드포인트) → ALB(AWS Load Balancer Controller가 Ingress로 생성) → EKS(t3.medium, Karpenter) 위 user/product/stress + RDS(Proxy) + S3 이미지. **T+60분 트래픽 시작 전 완료가 목표** — 아래를 위에서 아래로 실행한다. 설계 근거·당일 변경 절차·인스턴스 타입별 튜닝은 [ARCHITECTURE.md](ARCHITECTURE.md).

```
task-3/
├── terraform/   # VPC·ECR·RDS(+Proxy)·S3·CloudFront·WAF(+로그)   (ALB는 여기 없다)
├── eksctl/      # 클러스터 + MNG 1대 + addon 2개 + product SA
├── scripts/     # Karpenter·LBC 설치 (공식 문서 기반, CloudShell 실행)
├── k8s/         # EC2NodeClass/NodePool, 앱별 Deploy+Svc+HPA, Ingress(ALB 전체)
├── db/          # DB 초기화 SQL
└── app/         # Dockerfile (참고용 — 빌드는 당일 직접)
```

## 실행 위치 세 곳

각 코드 블록 첫 줄 라벨을 보고 해당 위치에 붙여넣는다.

| 위치 | 하는 일 | 필요한 것 |
|---|---|---|
| **본 PC (PowerShell 7)** | terraform, eksctl **뿐** | `terraform.exe`, `eksctl.exe`, `aws.exe` (PATH, 설치 후 새 창) |
| **VPC CloudShell** | 이미지 빌드/푸시, DB 초기화 | 콘솔 `+` → **Create VPC environment** (VPC `skills-vpc` / private subnet / SG `skills-cloudshell-sg`) |
| **리전 CloudShell** (일반) | kubectl·helm 전부 | 그냥 CloudShell 열기 (ap-northeast-2) |

`helm.exe`·`kubectl.exe`는 본 PC에 **필요 없다**. 리전 CloudShell에서 돌린다.

**VPC CloudShell 제약** (공식 문서):
- **Actions → Upload/Download 를 못 쓴다.** 제공 바이너리는 S3 콘솔로 수동 업로드해서 `aws s3 cp`로 받는다(STEP 3).
- **홈이 비영구**다. 세션이 끊기면 받은 파일이 사라진다 → S3에 올려둔 바이너리가 곧 복구 수단이다.
- IAM 사용자당 VPC 환경은 **최대 2개**. STEP 3·4는 같은 환경 하나를 재사용한다.
- private subnet + NAT라 인터넷·ECR 접근은 된다. mysql 클라이언트만 없어서 직접 설치한다.

**파일 전달은 복사·붙여넣기다.** 매니페스트·스크립트·SQL·dump 전부 `cat > 파일 <<'EOF'` 뒤에 붙여넣는다. S3를 거치는 것은 붙여넣을 수 없는 바이너리 3개뿐이다.

**ALB는 Terraform이 아니라 Ingress가 만든다.** 그래서 CloudFront(=제출 엔드포인트)는 STEP 8 이후에야 생성 가능하다.

## 순서 제약 (건너뛰면 조용히 깨지는 곳)

1. **STEP 1a 완료 → STEP 2·3 시작.** 진행 중인 apply의 state에서 output을 읽으면 `Output not found`. ECR 레포·S3 버킷도 1a 산물이다.
2. **STEP 1b 완료 → STEP 4.** RDS 엔드포인트가 있어야 붙는다.
3. **STEP 2 완료 → STEP 5.** `aws eks update-kubeconfig`가 클러스터를 필요로 한다.
4. **STEP 5(Karpenter) → STEP 7(NodePool).** 컨트롤러가 CRD를 깔기 전에는 NodePool을 apply할 수 없다.
5. **STEP 6(LBC) → STEP 8(Ingress).** LBC가 없으면 Ingress의 ADDRESS가 영원히 비어 있다.
6. **STEP 8(ADDRESS 확인) → STEP 9.** `data "aws_lb"`가 그 ALB를 이름으로 조회한다.

---

## STEP 0 — 사전 준비 (본 PC)

당일 과제지와 대조해 먼저 아래를 손본다.

| 파일 | 확인할 값 |
|---|---|
| `terraform/terraform.tfvars` | `prefix`(모든 이름의 접두사), `bucket_name`(전역 유일), `db_identifier`, `db_password` |
| `terraform/variables.tf` | `apps`(앱 목록), `image_tag` |
| `terraform/locals.tf` | 리전·CIDR·DB 사양. 개별 이름을 과제지가 지정하면 해당 줄만 리터럴로 덮어쓴다 |

`prefix`를 바꾸면 terraform 밖의 짝도 같이 고친다 — `eksctl/cluster.yaml`의 `metadata.name`, `k8s/00-nodeclass.yaml`의 `role`·태그, `k8s/20-ingress.yaml`의 `load-balancer-name`, `scripts/*.sh`의 `CLUSTER_NAME`. 전체 목록은 [ARCHITECTURE.md](ARCHITECTURE.md)의 "파일 간 결합" 표.

```powershell
# ── 본 PC (PowerShell) ──
cd task-3
aws configure   # 지급 키 입력, region: ap-northeast-2
```

## STEP 1 — 선행 apply (본 PC, ~3분 + ~15분)

CloudFront·WAF·S3 정책은 ALB가 생겨야 하므로 STEP 9로 미룬다. apply를 **1a(짧음) / 1b(RDS, 김)** 로 나누는 근거는 [ARCHITECTURE.md](ARCHITECTURE.md).

### 1a — 네트워크·ECR·S3 (~3분)

```powershell
# ── 본 PC (PowerShell) ──
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
terraform -chdir=terraform output -json private_subnet_ids   # 2개 id가 에러 없이 나와야 한다
```

> 위 output이 성공하면 **두 번째 창에서 STEP 2를 시작**하고, CloudShell에서 STEP 3을 시작한다.

### 1b — RDS + Proxy (~15분, STEP 2·3과 병렬)

이 target 하나가 DB 인스턴스·프록시·Secret·SG·IAM 역할을 전부 물고 온다.

```powershell
# ── 본 PC (PowerShell, 첫 번째 창) ──
terraform -chdir=terraform apply -auto-approve "-target=aws_db_proxy_target.this"

aws secretsmanager describe-secret --secret-id skills-db-credentials --query VersionIdsToStages
# {"<uuid>": ["AWSCURRENT"]} 이 나와야 한다. {} 또는 null이면 secret이 비어 있어
# 프록시가 DB에 인증하지 못한다 → terraform apply를 target 없이 다시 실행
```

## STEP 2 — eksctl 클러스터 생성 (본 PC, ~20분)

`eksctl/cluster.yaml`을 **편집기로 열어** 서브넷 id 4개를 직접 써넣는다. 값은 아래 두 명령의 출력이다.

```powershell
# ── 본 PC (PowerShell, 두 번째 창) ──
cd task-3
terraform -chdir=terraform output -json private_subnet_ids   # → subnet-REPLACE_PRIVATE_A / _B
terraform -chdir=terraform output -json public_subnet_ids    # → subnet-REPLACE_PUBLIC_A / _B

Select-String 'REPLACE' eksctl/cluster.yaml   # 출력이 없어야 한다(치환 누락 검사)

eksctl create cluster -f eksctl/cluster.yaml   # kubeconfig 자동 병합
```

이 클러스터에는 Karpenter도 LBC도 들어있지 않다. 둘 다 STEP 5·6에서 CloudShell로 깐다.

## STEP 3 — 이미지 빌드/푸시 (S3 콘솔 → VPC CloudShell)

ECR 레포는 STEP 1a가 만들었다 — 레포명 = `variables.tf`의 `apps` 항목 = k8s 이미지명.

1. **본 PC**: S3 콘솔에서 STEP 1a가 만든 버킷을 열고 `_bin/` 접두사로 제공 바이너리 3개(`user`·`product`·`stress`)를 업로드한다.
2. **VPC CloudShell**을 만든다: 콘솔 `+` → Create VPC environment → VPC `skills-vpc`, **private subnet 하나**(public을 고르면 인터넷이 안 된다 — NAT 경유만 된다), SG `skills-cloudshell-sg`(STEP 1a가 만들었다).

```bash
# ── VPC CloudShell ──
BUCKET=<bucket_name>            # terraform output bucket_name
ACCT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCT.dkr.ecr.ap-northeast-2.amazonaws.com
TAG=v1                          # terraform의 image_tag 변수와 반드시 일치

aws s3 cp s3://$BUCKET/_bin/ . --recursive
chmod +x user product stress
file user product stress        # dynamically / statically linked 확인

aws ecr get-login-password | docker login --username AWS --password-stdin $REG
```

여기서부터 **빌드와 push는 직접 한다.** `app/Dockerfile`을 참고해 앱마다 Dockerfile을 만들고 `docker build` → `docker push $REG/<app>:$TAG`. 베이스는 glibc가 있는 `gcr.io/distroless/base-debian13`이 안전하다 — static 베이스에 동적 링크 바이너리를 넣으면 `exec /app/server: no such file or directory`로 즉사한다(없는 것은 바이너리가 아니라 ELF 인터프리터다).

push 후 확인·정리:

```bash
# ── VPC CloudShell ──
aws ecr describe-images --repository-name user --query 'imageDetails[].imageTags' --output text
aws s3 rm s3://$BUCKET/_bin/ --recursive   # /images/* 로 노출되지 않게 지운다
```

> **docker가 VPC 환경에서 안 되면** 이미지 빌드만 리전 CloudShell로 옮긴다. 바이너리가 S3에 있으므로 위 `aws s3 cp` 한 줄로 그대로 이어진다.

## STEP 4 — DB 초기화 (VPC CloudShell)

STEP 1b가 끝났으면 실행 가능하며 STEP 5~9와 병행해도 된다. **dump 적재만 느리므로 VPC CloudShell 탭을 하나 더 열어 겹쳐 돌린다.**

**먼저 과제지의 스키마와 `db/01-schema.sql`을 대조한다.** 다르면 붙여넣기 전에 고친다.

```bash
# ── VPC CloudShell ──
sudo dnf install -y mariadb105
DB=<db_endpoint>                # terraform output db_endpoint (프록시 아님 — 직결)
mysql -h $DB -u admin -p dev    # password: terraform.tfvars의 db_password
```

1. **스키마** — 위 접속을 `:exit` 로 빠져나온 뒤, 로컬 `db/01-schema.sql` 내용을 붙여넣어 파일로 만들고 적재한다.

   ```bash
   cat > 01-schema.sql <<'EOF'
   # ← 로컬 db/01-schema.sql 내용을 여기에 붙여넣는다
   EOF
   mysql -h $DB -u admin -p dev < 01-schema.sql
   ```

2. **admin 유저 native 플러그인 전환** — 프록시 클라이언트 인증이 MySQL Native(`terraform/rds-proxy.tf`)라 백엔드 admin도 native여야 한다. `mysql>` 프롬프트에서 직접 입력한다(비밀번호가 들어가므로 파일로 남기지 않는다):

   ```sql
   ALTER USER 'admin'@'%' IDENTIFIED WITH mysql_native_password BY '<PASSWORD>';
   ```

   > 여기까지 끝나면 앱은 빈 테이블에 정상 연결된다 — STEP 5~8을 먼저 진행해도 된다.

3. **제공 dump 적재** (느림) — 본 PC에서 `load_user.dump`를 편집기로 열어 아래 heredoc에 붙여넣는다.

   ```bash
   cat > load_user.dump <<'EOF'
   # ← load_user.dump 내용을 여기에 붙여넣는다
   EOF
   mysql -h $DB -u admin -p dev < load_user.dump
   ```

4. **email 인덱스** (`db/02-index.sql`, dump 적재 **후**) — `GET /v1/user?email=`이 유일한 조회 패턴인데 과제지 스키마에 email 인덱스가 없다(풀스캔 = 0.2s SLO 전멸). dump가 DROP/CREATE TABLE을 포함할 수 있으므로 반드시 dump 뒤다.

   ```bash
   mysql -h $DB -u admin -p dev -e 'ALTER TABLE user ADD INDEX idx_email (email);'
   ```

5. **검증** — `mysql>`에서:

   ```sql
   SELECT COUNT(*) FROM user;
   SHOW INDEX FROM user;
   SELECT user, plugin FROM mysql.user WHERE user='admin';
   ```

   기대값: 행 수 = dump 건수, `idx_email` 존재, plugin = `mysql_native_password`.

## STEP 5 — Karpenter 설치 (리전 CloudShell)

STEP 2의 `eksctl create`가 끝난 뒤. 이 한 줄이 채점 경로와 동일하므로 여기서 실패하면 k8s 채점이 통째로 날아간다.

```bash
# ── 리전 CloudShell ──
aws eks update-kubeconfig --name skills-eks --region ap-northeast-2
kubectl get nodes    # Ready 1개
```

`scripts/karpenter.sh`를 붙여넣어 실행한다. IAM 역할·인터럽션 큐·access entry·SG 태그·Helm 설치를 순서대로 처리한다(~3분).

```bash
# ── 리전 CloudShell ──
cat > karpenter.sh <<'EOF'
# ← 로컬 scripts/karpenter.sh 내용을 여기에 붙여넣는다
EOF
bash karpenter.sh
```

Helm은 `replicas=1`로 깔린다 — 차트 기본값 2는 두 번째 replica가 Pending이 되어 Karpenter가 자기 자신을 위한 노드를 띄운다. 유휴 EC2 1대가 비용 ratio의 전제라 처음부터 1이다.

## STEP 6 — AWS Load Balancer Controller 설치 (리전 CloudShell)

```bash
# ── 리전 CloudShell ──
cat > lbc.sh <<'EOF'
# ← 로컬 scripts/lbc.sh 내용을 여기에 붙여넣는다
EOF
bash lbc.sh
```

마지막 `kubectl get ingressclass alb`가 나와야 한다 — 없으면 Ingress가 무시된다.

## STEP 7 — 노드풀 적용 (리전 CloudShell)

```bash
# ── 리전 CloudShell ──
cat > 00-nodeclass.yaml <<'EOF'
# ← 로컬 k8s/00-nodeclass.yaml 내용
EOF
cat > 01-nodepool.yaml <<'EOF'
# ← 로컬 k8s/01-nodepool.yaml 내용
EOF

kubectl apply -f 00-nodeclass.yaml -f 01-nodepool.yaml
kubectl get ec2nodeclass,nodepool   # Ready 확인
```

## STEP 8 — 앱 + Ingress 배포 (리전 CloudShell)

**본 PC에서 `k8s/10-user.yaml`·`11-product.yaml`·`12-stress.yaml`을 편집기로 열어 placeholder를 실제 값으로 채운 뒤** 붙여넣는다. 값은 본 PC에서 아래로 읽는다.

```powershell
# ── 본 PC (PowerShell) ──
terraform -chdir=terraform output -json ecr_image_uris   # <IMAGE> (3개, 태그 포함)
terraform -chdir=terraform output -raw db_proxy_endpoint # <PROXY_ENDPOINT>
terraform -chdir=terraform output -raw db_port           # <DB_PORT>
terraform -chdir=terraform output -raw db_password       # <DB_PASSWORD>
terraform -chdir=terraform output -raw bucket_name       # <BUCKET_NAME> (product만)
```

| placeholder | 값 | 들어가는 파일 |
|---|---|---|
| `<IMAGE>` | `ecr_image_uris.<app>` | 앱 3파일 각각 |
| `<PROXY_ENDPOINT>` | `db_proxy_endpoint` | user, product |
| `<DB_PORT>` | `db_port` | user, product |
| `<DB_PASSWORD>` | `db_password` | user, product |
| `<BUCKET_NAME>` | `bucket_name` | product |

```bash
# ── 리전 CloudShell ──
cat > 10-user.yaml <<'EOF'
# ← 값을 채운 로컬 k8s/10-user.yaml 내용
EOF
cat > 11-product.yaml <<'EOF'
# ← 값을 채운 로컬 k8s/11-product.yaml 내용
EOF
cat > 12-stress.yaml <<'EOF'
# ← 값을 채운 로컬 k8s/12-stress.yaml 내용
EOF
cat > 20-ingress.yaml <<'EOF'
# ← 로컬 k8s/20-ingress.yaml 내용 (채울 값 없음)
EOF

grep -nE '^[^#]*<[A-Z_]+>' ./*.yaml    # 출력이 없어야 한다 (placeholder 잔존 검사)

kubectl apply -f 10-user.yaml -f 11-product.yaml -f 12-stress.yaml -f 20-ingress.yaml
kubectl get pods -w                    # Running 확인
kubectl get ingress skills -w          # ADDRESS에 ALB DNS가 뜰 때까지 (~3분)
```

ADDRESS가 비어 있으면 `kubectl -n kube-system logs deploy/aws-load-balancer-controller`로 원인을 본다. 흔한 원인은 퍼블릭 서브넷의 `kubernetes.io/role/elb` 태그 누락(terraform `vpc.tf`)이다.

## STEP 9 — CloudFront 생성 + 엔드포인트 제출 (본 PC)

Ingress의 ADDRESS가 뜬 뒤 실행한다. `data "aws_lb"`가 그 ALB를 조회해 origin에 건다. WAF와 그 CloudWatch 로그 그룹도 여기서 생긴다.

```powershell
# ── 본 PC (PowerShell) ──
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.
CloudFront는 `wait_for_deployment=false`라 도메인이 즉시 나온다(전파는 몇 분 더 걸린다).

## STEP 10 — 스모크 (리전 CloudShell)

`/images/...` 오브젝트 키는 실제 업로드 결과로 바꾼다.

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

c "$CF/v1/none?$Q"                                                           # 404 (Ingress fixed-response)
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                    # 403 (WAF SQLi)
```

## STEP 11 — 유휴 1대 확인 (리전 CloudShell)

**비용 ratio의 전제**다. 트래픽이 없을 때 running EC2가 1대여야 한다.

```bash
# ── 리전 CloudShell ──
kubectl get nodes                                                  # 1개
kubectl -n kube-system get deploy karpenter                        # 1/1
kubectl -n kube-system get deploy aws-load-balancer-controller     # 1/1
kubectl get pods -A --field-selector status.phase=Pending          # 비어 있어야 한다
kubectl get nodeclaims                                             # 유휴 시 0개
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'length(Reservations[].Instances[])'                     # 1
```

Pending 파드가 하나라도 남아 있으면 Karpenter가 노드를 띄워 1대가 깨진다 — 4번째 명령이 핵심이다.
노드 1대에 안 들어가면 조정 순서는 ① `kubectl -n kube-system scale deploy/coredns --replicas=1`
→ ② 앱 requests 200m로 → ③ MNG를 2대로 (본 PC에서 `eksctl scale nodegroup`).

## STEP 12 — 운영 (리전 CloudShell + 콘솔)

```bash
# ── 리전 CloudShell ──
kubectl top nodes; kubectl top pods; kubectl get hpa -w   # 스케일 동작 관찰
kubectl get nodeclaims -w                                 # Karpenter 노드 증감
kubectl logs -f deploy/user                               # 앱 access log (stdout)
```

콘솔에서 볼 것:
- CloudWatch(**us-east-1**) → Logs Insights → 로그 그룹 `aws-waf-logs-skills-waf` (`terraform output waf_log_group`)
- WAF 콘솔(us-east-1) → sampled requests: SQLi·KnownBadInputs 룰 매치 확인

당일 변경:
- 특정 공격 패턴 추가 차단: `terraform/waf.tf`에 관리형 룰 블록 추가([ARCHITECTURE.md](ARCHITECTURE.md)의 붙여넣기용 블록)
- DB 엔진·API·인스턴스 타입 변경 절차: [ARCHITECTURE.md](ARCHITECTURE.md)의 "당일 변경 시나리오"
