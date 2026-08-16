# module-2-analytics — Linux 런북 (개인 리눅스 로컬 전용)

대회 본 PC 는 Windows 11 + PowerShell 7 이다. 대회에서는 [README.md](README.md) 의 PowerShell 런북을 쓰고, 이 파일은 개인 리눅스 환경에서 연습·검증할 때만 쓴다. bastion·CloudShell 안에서 실행하는 bash 절차는 이 파일이 아니라 README.md 에 있다.

bastion/CloudShell도 리눅스라 그대로 동작하지만, 이 섹션의 목적은 로컬 리눅스에서의 연습·검증이다.

```bash
aws configure set region ap-northeast-2
ALB_DNS=$(aws elbv2 describe-load-balancers --names wsc2026-analytics-alb --query "LoadBalancers[0].DNSName" --output text)
EC2_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-analytics-ec2" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)

# 2-1 EC2 서브넷 (analytics-priv-a)
aws ec2 describe-subnets --subnet-ids $(aws ec2 describe-instances --instance-ids $EC2_ID --query "Reservations[0].Instances[0].SubnetId" --output text) --query "Subnets[0].Tags[?Key=='Name'].Value|[0]" --output text
# 2-2 리스너 80 HTTP / TG wsc2026-analytics-tg 5000
aws elbv2 describe-listeners --load-balancer-arn $(aws elbv2 describe-load-balancers --names wsc2026-analytics-alb --query "LoadBalancers[0].LoadBalancerArn" --output text) --query "Listeners[].[Port,Protocol]" --output text
aws elbv2 describe-target-groups --names wsc2026-analytics-tg --query "TargetGroups[].[TargetGroupName,Port]" --output text
# 2-3-A 스트림 ACTIVE ON_DEMAND
aws kinesis describe-stream-summary --stream-name wsc2026-order-stream --query "StreamDescriptionSummary.[StreamName,StreamStatus,StreamModeDetails.StreamMode]" --output text
# 2-3-B / 2-5 앱 동작
curl -s -X POST http://$ALB_DNS/order | jq .
curl -s http://$ALB_DNS/health          # {"status":"healthy"}
# 2-4 Flink READY ZEPPELIN-FLINK-3_0
aws kinesisanalyticsv2 describe-application --application-name wsc2026-analytics-flink --query "ApplicationDetail.[ApplicationName,ApplicationStatus,RuntimeEnvironment]" --output text
# 2-6 systemd (active / enabled)
CMD_ID=$(aws ssm send-command --instance-ids $EC2_ID --document-name "AWS-RunShellScript" --parameters '{"commands":["systemctl is-active app && systemctl is-enabled app"]}' --query "Command.CommandId" --output text); sleep 3; aws ssm get-command-invocation --command-id $CMD_ID --instance-id $EC2_ID --query "StandardOutputContent" --output text
```

