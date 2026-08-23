# Module 4 — Linux 런북 (개인 리눅스 로컬 전용)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, bastion·CloudShell 단계는 자리에 stub 으로 표시했다. 대회 본 PC(Windows 11 + PowerShell 7)에서는 README.md 를 쓴다.

### 0) [본 PC] 리전 + 인증 경로 판별

리전은 이 셸에서 한 번만 잡아두면 3·4·6단계와 teardown 이 전부 이걸 쓴다. 새 터미널을 열었으면
다시 잡는다 — 안 잡힌 셸에서 3단계를 돌리면 다른 리전을 조회해 ESM 이 `None`, DynamoDB 가 0 으로
나온다(리소스는 멀쩡한데 안 보이는 것).

배부물 바이너리를 `../provided/module4/app` 에 먼저 놓는다(저장소엔 문서만 있다) — 없으면 `select-auth-mode` 가 "제공 바이너리 없음"(exit 2)으로 멈춘다. iam 판정에 대비해 자체 바이너리 `app/producer` 가 LFS 포인터(133B)가 아니라 실물(약 10MB)인지도 확인한다 — 포인터면 `git lfs pull`.

그날 지급된 제공 바이너리가 IAM 인증을 지원하는지에 따라 1단계 apply 명령이 갈린다:

```bash
# cwd: module-4-msk
export AWS_DEFAULT_REGION=ap-northeast-1

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
export NUM=$(jq -r '.player_number.value' outputs.json)
export CLUSTER_ARN=$(jq -r '.cluster_arn.value' outputs.json)
export BOOTSTRAP=$(jq -r '.bootstrap_brokers_sasl_iam.value' outputs.json)   # IAM 9098
export TOPIC_RAW=wsc2026-sensor-raw
export BUCKET=$(jq -r '.alert_bucket.value' outputs.json)
export BASTION_IP=$(jq -r '.bastion_public_ip.value' outputs.json)
EOF

source .env
```

bastion 으로 올린다. SSM 경로가 기본이다 — 22 를 안 거치므로 아웃바운드 22 가 막힌 망에서도 된다:

```bash
BID=$(terraform output -raw bastion_instance_id)
ENV_B64=$(base64 -w0 .env)
aws ssm send-command --instance-ids "$BID" --document-name AWS-RunShellScript \
  --parameters "commands=[\"echo $ENV_B64 | base64 -d > /home/ec2-user/.env\",\"chown ec2-user:ec2-user /home/ec2-user/.env\"]" \
  --query "Command.CommandId" --output text
```

22 가 열려 있는 망이면 `scp .env ec2-user@$BASTION_IP:~/.env` (비번 `Skill53##`) 도 된다. 대회장 망은
22 를 막을 수 있고(채점이 전부 CloudShell/콘솔 443 이라 주최측이 열어둘 이유가 없다), 위 `send-command`
경로는 로컬에 Session Manager plugin 도 필요 없다.

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

실측에서는 두 루프 모두 1회에 통과했다. 여러 바퀴 돌면 producer 쪽을 본다. `send-command` 를 부팅 후 2~3분 안에 치면 SSM agent 미등록으로 `InvalidInstanceId`. `get-command-invocation` 은 명령이 끝나기 전에 조회하면 `InvocationDoesNotExist` — 몇 초면 끝나는 명령이라 5초면 충분하다. 둘 다 나면 몇 분 뒤 재시도.

```bash
sleep 180    # SSM agent 등록 대기 (send-command 전, 1회만)

PID=$(terraform output -raw producer_instance_id)
CMD=$(aws ssm send-command --instance-ids "$PID" --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl is-active app","journalctl -u app -n 20 --no-pager","tail -30 /var/log/cloud-init-output.log"]' \
  --query "Command.CommandId" --output text)

sleep 5    # 명령 실행 완료 대기
aws ssm get-command-invocation --command-id "$CMD" --instance-id "$PID" --query "StandardOutputContent" --output text
```

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

개별 바이너리 판별(cwd: module-4-msk): `./check-binary-auth.sh app/producer` / `./check-binary-auth.sh ../provided/module4/app`. 모드 판별 자체는 0단계 `./select-auth-mode.sh`.

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

### destroy 가 private 서브넷·VPC 삭제에서 멈출 때 — Lambda/MSK ENI 정리

`msk-priv-a`·`msk-priv-d` 와 `msk-vpc` 삭제가 `DependencyViolation` 으로 걸리면 VPC Lambda·MSK ESM 의 Hyperplane ENI 가 아직 회수되지 않은 것이다(배경은 [README.md](README.md) 같은 절). 5~10분 뒤 재시도 → 그래도 걸리면 `teardown-eni.sh` 로 직접 정리한다. VPC ID 는 `terraform output vpc_id` 에서 자동으로 읽는다.

```bash
# cwd: module-4-msk (terraform/ 에서 왔다면 cd ..)
export AWS_DEFAULT_REGION=ap-northeast-1
chmod +x teardown-eni.sh
./teardown-eni.sh
```

Lambda Kafka 트리거 삭제 → 이 VPC 를 쓰는 Lambda 의 VPC 연결 해제 → 남은 ENI detach·delete 순으로 진행하고, 각 단계에서 지울 게 없으면(destroy 가 이미 지웠으면) 건너뛴다는 로그를 남긴다. 끝나면:

```bash
terraform destroy
```
