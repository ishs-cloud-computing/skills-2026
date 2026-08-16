# module-4-msk — Linux 런북 (개인 리눅스 로컬 전용)

대회 본 PC 는 Windows 11 + PowerShell 7 이다. 대회에서는 [README.md](README.md) 의 PowerShell 런북을 쓰고, 이 파일은 개인 리눅스 환경에서 연습·검증할 때만 쓴다. bastion·CloudShell 안에서 실행하는 bash 절차는 이 파일이 아니라 README.md 에 있다.

배포(리눅스 로컬):

```bash
# terraform.tfvars 의 player_number 를 본인 비번호로 먼저 수정한다 (-var 로 넘기지 않는다)
cd module-4-msk/terraform
pip install -r lambda/sensor_consumer/requirements.txt -t lambda/sensor_consumer/
terraform init
terraform apply
terraform output -json > outputs.json

# 재접속 대비 .env 준비 (작업규칙 6): 로컬 + bastion 양쪽
cat > .env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-1
export NUM=$NUM
export CLUSTER_ARN=$(jq -r '.cluster_arn.value' outputs.json)
export BOOTSTRAP=$(jq -r '.bootstrap_brokers_sasl_iam.value' outputs.json)   # IAM 9098 (bastion kafka CLI 용)
export TOPIC_RAW=wsc2026-sensor-raw
export BUCKET=$(jq -r '.alert_bucket.value' outputs.json)
export BASTION_IP=$(jq -r '.bastion_public_ip.value' outputs.json)
EOF

# 같은 .env 를 bastion 에도 배치 → 재접속 시 바로 source (client.properties 는 user_data 로 이미 있음)
source .env && scp .env ec2-user@$BASTION_IP:~/.env      # 비번: Skill53##

# 파이프라인 기동 확인 — 고정 대기 대신 폴링 (각 최대 10분)
for i in $(seq 1 40); do
  S=$(for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].State" --output text; done)
  echo "ESM: $S"; [ "$(echo "$S" | grep -cv '^Enabled$')" -eq 0 ] && break; sleep 15
done
for i in $(seq 1 40); do
  N=$(aws dynamodb scan --table-name wsc2026-sensor-data --select COUNT --query "Count" --output text)
  echo "items: $N"; [ "$N" -gt 0 ] && break; sleep 15
done
```

바이너리 판별·채점 전 정리(리눅스 로컬):

```bash
./check-binary-auth.sh app/producer      # cwd: module-4-msk
aws s3 rm "s3://$BUCKET/bin/app"         # 채점 전 정리 (마지막 apply 이후)
```

검증(리눅스 로컬 — 실제 채점은 bastion/CloudShell 에서 `mark/mark2-4.sh`):

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
# 4-5-C/D 이상치 경로 확인 (alert consumer → S3 + SNS publish 로그)
aws s3 ls s3://$BUCKET/alert/ --recursive | head
aws logs tail /aws/lambda/wsc2026-sensor-alert-consumer --since 15m --format short | grep "alert forwarded"
aws logs tail /aws/lambda/wsc2026-sensor-consumer --since 15m --format short | grep "ALERT -"   # 위가 비면 여기부터
```

