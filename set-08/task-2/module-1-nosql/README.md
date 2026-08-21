# Module 1 — DocumentDB NoSQL (ap-northeast-2)

DocumentDB 클러스터 + Client EC2(지급 `docdb_client.py`) + Secrets Manager + KMS. 채점은 CloudShell 에서 `mark/mark2-1.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다 (CloudShell 단계는 공통).

## 디렉토리 구조

```
module-1-nosql/
├── terraform/
│   ├── vpc.tf                 # VPC(10.63/16) + public 서브넷 1 + db 서브넷 2(AZ 2개) + subnet group
│   ├── sg.tf                  # client(8080 개방)·docdb(27017, client SG 소스만)
│   ├── docdb.tf               # KMS 키/alias + DocumentDB cluster/instance
│   ├── secrets.tf             # random_password + Secret(username/password/host)
│   ├── iam.tf                 # EC2 role: GetSecretValue 만
│   ├── ec2.tf                 # Client EC2 (AL2023, user-data)
│   ├── userdata.sh.tftpl      # pip 설치 + CA bundle + systemd serve + seed/index 재시도
│   ├── index_setup.py.tftpl   # 과제지 3-3 인덱스·TTL 생성 스크립트
│   └── {versions,variables,outputs}.tf
├── README.md
└── README.linux.md

# 앱·데이터: task-2/provided/module-1/{docdb_client.py,retail_dataset.json} (제공 원본, 수정 금지) — terraform 이 직접 참조
# 채점: task-2/mark/mark2-1.sh (CloudShell, ap-northeast-2)
```

## 1. 배포 (실측 ~7분: DocumentDB 인스턴스 생성이 병목)

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

## 2. 환경변수 (.env)

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-2"
$env:NOSQL_CLIENT_IP    = terraform -chdir=terraform output -raw client_public_ip
$env:DOCDB_ENDPOINT     = terraform -chdir=terraform output -raw docdb_endpoint

@"
`$env:AWS_DEFAULT_REGION = "ap-northeast-2"
`$env:NOSQL_CLIENT_IP    = "$env:NOSQL_CLIENT_IP"
`$env:DOCDB_ENDPOINT     = "$env:DOCDB_ENDPOINT"
"@ | Set-Content .env.ps1

. .\.env.ps1   # 재접속 시: module-1-nosql 디렉터리에서 `. .\.env.ps1` 만 다시 실행
```

## 3. 검증 (pip 설치 + seed/index 재시도 루프 — 실측으로는 apply 직후 바로 200)

```powershell
while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://$($env:NOSQL_CLIENT_IP):8080/health") -ne "200") { Start-Sleep 15 }

curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/health"
# → {"status": "ok", "database": "skills_retail", "port": 27017, "tls": true}

curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/admin/summary"
# → counts: orders 8 / products 6 / sessions 3, dateFieldTypes 전부 "datetime"

curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/admin/indexes"
# → orders 4개(_id 포함)·products 3개·sessions 4개, sessions.expiresAt 에 expireAfterSeconds: 0

curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/orders/O-1001"
# → orderId=O-1001, customerId=C001, status=PENDING, warehouseId=W-A
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/customers/C001/orders"
# → O-1006, O-1001, O-1004 포함 (createdAt DESC)
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
# → O-1001, O-1003, O-1006 포함 (dueAt ASC). O-1007 은 dueAt 2026-06-12 라 제외되는 게 정답
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/products/low-stock?warehouseId=W-A"
# → P-BLU-003, P-RED-001 포함 / P-GRN-002 미포함
```

### AWS 측 사전 점검 (채점 1-1 / 1-2)

HTTP 엔드포인트만 보면 DocumentDB·KMS·Secret 의 오설정이 채점 때야 드러난다. `mark2-1.sh:47-55` 와 같은 조회를 미리 돌린다.

```powershell
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
# mark/mark2-1.sh 를 CloudShell 에 업로드(작업 → 파일 업로드) 후 실행. 저장소가 private 이라 git clone 은 쓰지 않는다.
# Windows 업로드 시 CRLF 가드 (멱등):
sed -i 's/\r$//' mark2-1.sh
bash mark2-1.sh
```

## 4. Teardown

```powershell
terraform -chdir=terraform destroy -auto-approve
```
