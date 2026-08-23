# Module 2 — Linux 런북 (개인 리눅스 로컬 전용)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, 콘솔·Zeppelin·CloudShell 단계는 자리에 stub 으로 표시했다. 대회 본 PC(Windows 11 + PowerShell 7)에서는 README.md 를 쓴다.

### 1) [본 PC] 배포

배부물 `app.py`·`requirements.txt` 를 `../../provided/module2/` 에 먼저 놓는다 — `ec2.tf` 가 `file()` 로 직접 읽으므로 없으면 plan 단계에서 실패한다.

```bash
cd terraform
terraform init
terraform apply; terraform output -json > outputs.json
```

apply 후 EC2 user_data(pip 설치)와 TG 헬스체크까지 2~3분 대기.

### 2) [본 PC] 리소스 검증

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
ALB_DNS=$(aws elbv2 describe-load-balancers --names wsc2026-analytics-alb --query "LoadBalancers[0].DNSName" --output text)
EC2_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-analytics-ec2" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)

# 2-1 EC2 서브넷 (analytics-priv-a)
aws ec2 describe-subnets --subnet-ids $(aws ec2 describe-instances --instance-ids $EC2_ID --query "Reservations[0].Instances[0].SubnetId" --output text) --query "Subnets[0].Tags[?Key=='Name'].Value|[0]" --output text
# 2-2 리스너 80 HTTP / TG wsc2026-analytics-tg 5000
aws elbv2 describe-listeners --load-balancer-arn $(aws elbv2 describe-load-balancers --names wsc2026-analytics-alb --query "LoadBalancers[0].LoadBalancerArn" --output text) --query "Listeners[].[Port,Protocol]" --output text
aws elbv2 describe-target-groups --names wsc2026-analytics-tg --query "TargetGroups[].[TargetGroupName,Port]" --output text
# 2-3 스트림 ACTIVE ON_DEMAND
aws kinesis describe-stream-summary --stream-name wsc2026-order-stream --query "StreamDescriptionSummary.[StreamName,StreamStatus,StreamModeDetails.StreamMode]" --output text
# 2-4 / 2-6 앱 동작
curl -s -X POST http://$ALB_DNS/order | jq .
curl -s http://$ALB_DNS/health          # {"status":"healthy"}
# 2-5 Flink READY ZEPPELIN-FLINK-3_0
aws kinesisanalyticsv2 describe-application --application-name wsc2026-analytics-flink --query "ApplicationDetail.[ApplicationName,ApplicationStatus,RuntimeEnvironment]" --output text
# 2-7 systemd (active / enabled)
CMD_ID=$(aws ssm send-command --instance-ids $EC2_ID --document-name "AWS-RunShellScript" --parameters '{"commands":["systemctl is-active app && systemctl is-enabled app"]}' --query "Command.CommandId" --output text); sleep 3; aws ssm get-command-invocation --command-id $CMD_ID --instance-id $EC2_ID --query "StandardOutputContent" --output text
```

### 3) [AWS 콘솔] Studio 노트북 실행

[README.md](README.md) 3단계 수행.

### 4) [본 PC] 데이터 주입

```bash
for i in $(seq 1 30); do curl -s -X POST http://$ALB_DNS/orders/generate > /dev/null; done
```

### 5) [Zeppelin] 문단 순차 실행

[README.md](README.md) 5단계 수행 — SQL 문단은 셸과 무관하게 동일하다.

### 6) [AWS 콘솔] 시연 후 노트북 중지

[README.md](README.md) 6단계 수행.

### 7) [CloudShell] 셀프 채점

[README.md](README.md) 7단계 수행.

## Teardown

```bash
cd terraform
terraform destroy
```
