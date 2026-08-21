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
n=0; until [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${NOSQL_CLIENT_IP}:8080/health")" = "200" ] || [ $n -ge 40 ]; do sleep 15; n=$((n+1)); done   # 상한 10분

curl -s "http://${NOSQL_CLIENT_IP}:8080/health"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/admin/summary"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/admin/indexes"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/orders/O-1001"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/customers/C001/orders"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
curl -s "http://${NOSQL_CLIENT_IP}:8080/v1/products/low-stock?warehouseId=W-A"
# 기대값은 README.md 3단계와 동일
```

### AWS 측 사전 점검 (채점 1-1 / 1-2)

HTTP 엔드포인트만 보면 DocumentDB·KMS·Secret 의 오설정이 채점 때야 드러난다. `mark2-1.sh:47-55` 와 같은 조회를 미리 돌린다.

```bash
aws docdb describe-db-clusters --region ap-northeast-2 --db-cluster-identifier skills-nosql-docdb-cluster --query 'DBClusters[0].{Status:Status,Encrypted:StorageEncrypted,BackupRetention:BackupRetentionPeriod,Port:Port}' --output table
# → Status=available / Encrypted=True / BackupRetention>=1 / Port=27017

aws docdb describe-db-instances --region ap-northeast-2 --db-instance-identifier skills-nosql-docdb-instance-1 --query 'DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass}' --output table
# → Status=available / Class=db.t3.medium

aws kms describe-key --region ap-northeast-2 --key-id alias/skills-nosql-docdb --query 'KeyMetadata.{Enabled:Enabled,KeyManager:KeyManager}' --output table
# → Enabled=True / KeyManager=CUSTOMER   (AWS 였다면 고객관리 CMK 가 아니라는 뜻이라 1-1 미충족)

aws secretsmanager get-secret-value --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query SecretString --output text | jq -r '{username, host, password_set:(.password != null and .password != "")}'
# → password_set=true, host 는 scheme·port 없는 hostname (`://` 나 `:` 가 있으면 1-2·1-3·1-5 가 함께 깨진다)

aws secretsmanager describe-secret --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query '{Name:Name,KmsKeyId:KmsKeyId}' --output table
# → KmsKeyId 가 None 인 것은 정상이다 (AWS 관리형 키 사용, 채점 판정 문장에 없는 항목)
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
