# task-3 — System operation (Linux bash 버전)

[README.md](README.md)의 PowerShell 런북과 동일한 절차의 bash 판. 본 컴퓨터가 Linux/macOS이거나
전부 CloudShell에서 돌릴 때 사용한다. 설계 근거는 [ARCHITECTURE.md](ARCHITECTURE.md).

PowerShell 판과의 차이는 문법뿐이다.
- 값 읽기: `ConvertFrom-Json` → `jq`, placeholder 치환: `.Replace()` → `sed`.
- Linux엔 `aws`/`jq`/`sed`/`curl`이 있으므로 PowerShell이 우회했던 부분을 직접 쓴다.
- `curl`은 진짜 curl이다(`curl.exe` 불필요, `NUL` → `/dev/null`).

```
task-3/
├── terraform/   # VPC·ECR·RDS(+Proxy)·S3·ALB·CloudFront·WAF·노드 IAM
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
# 앱 목록·이미지 태그가 당일 과제와 다르면 terraform/variables.tf의 apps·image_tag,
# 리전·CIDR·DB 사양이 다르면 terraform/locals.tf 수정

# 지급된 자격증명을 파일로 저장(전 터미널 공유). terraform/eksctl/kubectl도 이 값을 읽는다.
aws configure   # 지급 키 입력, region: ap-northeast-2, output: json

export DB_PASSWORD='password'   # tfvars의 db_password와 동일하게 (STEP 8 치환용)
```

## STEP 1 — 선행 apply: 네트워크·노드롤 (로컬 bash, ~3분)

리프 리소스만 지정 — VPC·서브넷·IGW·NAT·라우트·노드롤은 종속성으로 딸려 온다.

```bash
# ── 로컬 bash ──
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve \
  -target=data.aws_caller_identity.current \
  -target=aws_vpc_endpoint.s3 \
  -target=aws_nat_gateway.this \
  -target=aws_route_table_association.public \
  -target=aws_route_table_association.private \
  -target=aws_iam_role_policy_attachment.node_minimal \
  -target=aws_iam_role_policy_attachment.node_ecr_pull \
  -target=aws_ecr_repository.app
```

## STEP 2 — eksctl 클러스터 생성 (로컬 bash, ~15분)

이 터미널은 생성이 끝날 때까지 점유되므로, **바로 STEP 3을 새 터미널에서 병렬로** 돌린다.

```bash
# ── 로컬 bash ──
# jq 인덱스로 직접 읽는다. bash 배열 ${arr[0]}은 zsh에서 1-index라 subnet-a가 비니 쓰지 않는다.
sn_json=$(terraform -chdir=terraform output -json private_subnet_ids)
sn_a=$(jq -r '.[0]' <<<"$sn_json")
sn_b=$(jq -r '.[1]' <<<"$sn_json")
acct=$(terraform -chdir=terraform output -raw account_id)

sed -e "s/subnet-REPLACE_A/${sn_a}/" \
    -e "s/subnet-REPLACE_B/${sn_b}/" \
    -e "s/ACCOUNT_ID/${acct}/" \
    eksctl/cluster.yaml > eksctl/cluster.rendered.yaml

eksctl create cluster -f eksctl/cluster.rendered.yaml   # kubeconfig 자동 병합
```

## STEP 3 — 전체 terraform apply (새 터미널, ~20분)

STEP 2와 병렬. 자격증명은 aws configure로 저장돼 전 터미널 공유 — **새 터미널에서는 `DB_PASSWORD`만 다시 export**한 뒤:

```bash
# ── 로컬 bash (두 번째 터미널) ──
cd task-3
terraform -chdir=terraform apply -auto-approve
```

RDS Multi-AZ·CloudFront 배포가 오래 걸린다. CloudFront 도메인은 배포 완료 전 확정되므로 STEP 6에서 미리 제출한다.

## STEP 4 — 이미지 빌드/푸시 (CloudShell, 바이너리 수령 즉시)

PowerShell 판과 동일 — 이 스텝은 원래 CloudShell이다. [README.md](README.md#step-4) STEP 4의 bash 블록 그대로 실행한다.
ECR 레포는 STEP 1 terraform이 생성했다(레포명 = `apps` 맵 키). Dockerfile 수정이 필요하면 `app/Dockerfile` 주석 참고.

## STEP 5 — 클러스터 완료 후 노드풀 적용 (로컬 bash)

STEP 2 터미널에서 `eksctl create`가 끝난 것을 확인한 뒤:

```bash
# ── 로컬 bash ──
kubectl apply -f k8s/00-nodeclass.yaml -f k8s/01-nodepool.yaml
kubectl get nodeclass,nodepool   # Ready 확인
```

## STEP 6 — 엔드포인트 제출 (로컬 bash)

앱 배포 전에 미리 제출한다(조기 제출 = 채점 이득).

```bash
# ── 로컬 bash ──
terraform -chdir=terraform output -raw cloudfront_domain
```

채점 플랫폼에 **`https://<위 도메인>`** 제출 — 프로토콜 포함, 경로 금지.

## STEP 7 — DB 초기화 (로컬 bash)

[db/README.linux.md](db/README.linux.md) 런북을 실행한다. 직결 엔드포인트 사용(프록시 X). **STEP 5 노드풀 Ready 필요** (mysql 클라이언트를 `kubectl run`으로 띄운다).
스키마 → admin native 전환 → **여기서 STEP 8을 새 터미널에서 시작** → dump 적재 → email 인덱스 → 검증 순.

## STEP 8 — 앱 배포: placeholder 치환 후 apply (로컬 bash)

**STEP 7의 2번(admin native 전환)이 끝났으면 dump 적재와 병행한다** — 앱은 빈 테이블에도 정상 연결되고(스키마 존재·인증 완료) 데이터는 T+60 트래픽 전에만 있으면 된다. 병행하면 노드 생성·이미지 pull·파드 기동·TG 등록·ALB 헬스체크가 dump 적재 뒤에 쌓이지 않는다.

env는 각 앱 매니페스트에 직접 들어있다. 한 파일씩 치환 후 apply.

sed 구분자로 `#`를 쓴다(URL·ARN에 없음). DB_PASSWORD에 `#`가 들어있으면 구분자를 바꾼다.

```bash
# ── 로컬 bash ──
proxy=$(terraform -chdir=terraform output -raw db_proxy_endpoint)
dbport=$(terraform -chdir=terraform output -raw db_port)
bucket=$(terraform -chdir=terraform output -raw bucket_name)
img_user=$(terraform    -chdir=terraform output -json ecr_image_uris | jq -r '.user')      # 태그 포함 full URI
img_product=$(terraform -chdir=terraform output -json ecr_image_uris | jq -r '.product')
img_stress=$(terraform  -chdir=terraform output -json ecr_image_uris | jq -r '.stress')
tg_user=$(terraform    -chdir=terraform output -json tg_arns | jq -r '.user')
tg_product=$(terraform -chdir=terraform output -json tg_arns | jq -r '.product')
tg_stress=$(terraform  -chdir=terraform output -json tg_arns | jq -r '.stress')

# user (DB만)
sed -e "s#<IMAGE>#$img_user#" \
    -e "s#<TG_ARN>#$tg_user#" \
    -e "s#<PROXY_ENDPOINT>#$proxy#" \
    -e "s#<DB_PORT>#$dbport#" \
    -e "s#<DB_PASSWORD>#$DB_PASSWORD#" \
    k8s/10-user.yaml | kubectl apply -f -

# product (DB + S3)
sed -e "s#<IMAGE>#$img_product#" \
    -e "s#<TG_ARN>#$tg_product#" \
    -e "s#<PROXY_ENDPOINT>#$proxy#" \
    -e "s#<DB_PORT>#$dbport#" \
    -e "s#<DB_PASSWORD>#$DB_PASSWORD#" \
    -e "s#<BUCKET_NAME>#$bucket#" \
    k8s/11-product.yaml | kubectl apply -f -

# stress (env 없음 — 이미지·TG만)
sed -e "s#<IMAGE>#$img_stress#" \
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

# user — POST(생성) → GET(조회). dbdump500001은 dump에 없어 신규 생성됨.
curl -s -o /dev/null -w "%{http_code} POST user\n" -X POST "$CF/v1/user?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","username":"dbdump500001","email":"dbdump500001@example.org"}'  # 201
c "$CF/v1/user?email=dbdump500001@example.org&$Q"                          # 200

# product — POST(생성) → GET(조회). 테이블은 비어 있음(dump는 user만).
curl -s -o /dev/null -w "%{http_code} POST product\n" -X POST "$CF/v1/product?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","id":"dbdump500001","name":"dbdump500001","price":1234}'  # 201
c "$CF/v1/product?id=dbdump500001&$Q"                                      # 200

# product 이미지 업로드(PUT, 멀티파트) → 동일 엔드포인트 /images 로 다운로드.
# ⚠ 멀티파트 필드명(image=@..)·업로드 후 오브젝트 키(/images/<key>)는 제공 바이너리로 확인 필수.
head -c 1024 /dev/urandom > /tmp/smoke.jpg
curl -s -o /dev/null -w "%{http_code} PUT product image\n" -X PUT "$CF/v1/product?$Q" \
  -F "requestid=999999999999" -F "uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729" \
  -F "id=dbdump500001" -F 'image=@/tmp/smoke.jpg'                          # 200
c "$CF/images/dbdump500001.jpg"                                           # 200 (PUT 업로드 후, 키는 바이너리 확인)

# stress (DB 미사용)
curl -s -o /dev/null -w "%{http_code} POST stress\n" -X POST "$CF/v1/stress?$Q" \
  -H 'Content-Type: application/json' \
  -d '{"requestid":"999999999999","uuid":"7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729","length":256}'  # 201

# 비정상 요청
c "$CF/v1/none?$Q"                                                         # 404
c "$CF/v1/user?email=%27%20OR%201=1--&$Q"                                  # 403 (WAF SQLi)

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
