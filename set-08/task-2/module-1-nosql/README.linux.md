# Module 1 — DocumentDB NoSQL (ap-northeast-2) — Linux 런북

PowerShell 대신 bash/zsh 용. 단계 구성은 [README.md](README.md) 와 1:1.

## 1. 배포 (실측 ~7분: DocumentDB 인스턴스 생성이 병목)

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

## 2. 환경변수 (.env)

```bash
export AWS_DEFAULT_REGION="ap-northeast-2"
export NOSQL_CLIENT_IP="$(terraform -chdir=terraform output -raw client_public_ip)"
export DOCDB_ENDPOINT="$(terraform -chdir=terraform output -raw docdb_endpoint)"

cat > .env <<EOF
export AWS_DEFAULT_REGION="ap-northeast-2"
export NOSQL_CLIENT_IP="${NOSQL_CLIENT_IP}"
export DOCDB_ENDPOINT="${DOCDB_ENDPOINT}"
EOF

source .env   # 재접속 시: module-1-nosql 디렉터리에서 `source .env` 만 다시 실행
```

## 3. 검증 (배포 후 대기 — 실측으로는 apply 직후 바로 200)

```bash
until [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${NOSQL_CLIENT_IP}:8080/health")" = "200" ]; do sleep 15; done

curl -s "http://${NOSQL_CLIENT_IP}:8080/health"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/admin/summary"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/admin/indexes"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/orders/O-1001"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/customers/C001/orders"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/products/low-stock?warehouseId=W-A"
# 기대값은 README.md 3단계와 동일
```

### [CloudShell] 셀프 채점

```bash
sed -i 's/\r$//' mark2-1.sh
bash mark2-1.sh
```

## 4. Teardown

```bash
terraform -chdir=terraform destroy -auto-approve
```
