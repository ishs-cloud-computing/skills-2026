# Module 4 — Linux 런북 (개인 리눅스 로컬 전용)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, bastion·CloudShell 단계는 자리에 stub 으로 표시했다. 대회 본 PC(Windows 11 + PowerShell 7)에서는 README.md 를 쓴다.

### 0) [본 PC] 인증 경로 판별

그날 지급된 제공 바이너리가 IAM 인증을 지원하는지에 따라 1단계 apply 명령이 갈린다:

```bash
# cwd: module-4-msk
./select-auth-mode.sh
```

출력된 apply 명령을 1단계에서 그대로 쓴다. 경로 비교는 [README.md](README.md) 의 "producer 인증 경로" 절.

### 1) [본 PC] 의존성 번들 + 배포

```bash
# terraform.tfvars 의 player_number 를 본인 비번호로 먼저 수정한다 (-var 로 넘기지 않는다)
cd terraform
pip install -r lambda/sensor_consumer/requirements.txt -t lambda/sensor_consumer/
terraform init

# 0단계가 iam 판정 → 아래 그대로. tls 판정 → -var "producer_auth_mode=tls" 를 붙인다.
terraform apply                       # 50 리소스 / 실측 35분 (MSK 하나가 31분 40초)

terraform output -json > outputs.json
```

### 2) [본 PC] `.env` 생성 + bastion 배치

```bash
cat > .env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-1
export NUM=$NUM
export CLUSTER_ARN=$(jq -r '.cluster_arn.value' outputs.json)
export BOOTSTRAP=$(jq -r '.bootstrap_brokers_sasl_iam.value' outputs.json)   # IAM 9098
export TOPIC_RAW=wsc2026-sensor-raw
export BUCKET=$(jq -r '.alert_bucket.value' outputs.json)
export BASTION_IP=$(jq -r '.bastion_public_ip.value' outputs.json)
EOF

source .env && scp .env ec2-user@$BASTION_IP:~/.env      # 비번: Skill53##
```

### 3) [본 PC] 파이프라인 기동 확인 (각 최대 10분)

```bash
for i in $(seq 1 40); do
  S=$(for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].State" --output text; done)
  echo "ESM: $S"; [ "$(echo "$S" | grep -cv '^Enabled$')" -eq 0 ] && break; sleep 15
done
for i in $(seq 1 40); do
  N=$(aws dynamodb scan --table-name wsc2026-sensor-data --select COUNT --query "Count" --output text)
  echo "items: $N"; [ "$N" -gt 0 ] && break; sleep 15
done
```

실측에서는 두 루프 모두 1회에 통과했다. 여러 바퀴 돌면 producer 쪽을 본다 — [README.md](README.md) 3단계의 SSM `send-command` 블록.

### 4) [본 PC] 리소스 검증

```bash
source .env
# 4-1 DynamoDB + S3
aws dynamodb describe-table --table-name wsc2026-sensor-data --query "Table.[TableName,KeySchema[*].AttributeName]" --output text && aws s3api head-bucket --bucket $BUCKET 2>&1
# 4-2 Lambda (python3.14)
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text; done
# 4-3 MSK
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" --output text
# 4-4 ESM Enabled ×2
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].[State]" --output text; done
# 4-5-A / 4-5-B
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 1 --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" --output json
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 3 --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" --output table
# 4-5-C/D 이상치 경로 (alert consumer → S3 + SNS publish 로그)
aws s3 ls s3://$BUCKET/alert/ --recursive | head
aws logs tail /aws/lambda/wsc2026-sensor-alert-consumer --since 15m --format short | grep "alert forwarded"
aws logs tail /aws/lambda/wsc2026-sensor-consumer --since 15m --format short | grep "ALERT -"   # 위가 비면 여기부터
```

개별 바이너리 판별(cwd: module-4-msk): `./check-binary-auth.sh app/producer`(정통 경로·기본 — IAM 지원) / `./check-binary-auth.sh ../provided/module4/app`(대회 제출 우회 — IAM 불가가 정상). 모드 판별 자체는 0단계 `./select-auth-mode.sh`.

### 5) [bastion·bash] kafka 디버깅 + 셀프 채점

[README.md](README.md) 5단계 수행.

### 6) [본 PC] 채점 전 정리 — S3 바이너리 제거

```bash
aws s3 rm "s3://$BUCKET/bin/app"
```

## Teardown

```bash
cd terraform
terraform destroy                     # 50 리소스 / 실측 23분 5초
```
