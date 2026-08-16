# module-3-event — Linux 런북 (개인 리눅스 로컬 전용)

대회 본 PC 는 Windows 11 + PowerShell 7 이다. 대회에서는 [README.md](README.md) 의 PowerShell 런북을 쓰고, 이 파일은 개인 리눅스 환경에서 연습·검증할 때만 쓴다. bastion·CloudShell 안에서 실행하는 bash 절차는 이 파일이 아니라 README.md 에 있다.

CloudShell에서도 동일 동작. 실제 채점은 `mark/mark2-3.sh` 를 그대로 실행하면 된다.

```bash
aws configure set region eu-west-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-event-ec2" "Name=instance-state-name,Values=running,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=wsc2026-event-sg" --query "SecurityGroups[0].GroupId" --output text)

# 3-1 SNS + Lambda (runtime python3.12)
aws sns get-topic-attributes --topic-arn arn:aws:sns:eu-west-1:${ACCOUNT_ID}:wsc2026-event-alert --query "Attributes.TopicArn" --output text
for fn in wsc2026-ec2-stop-remediation wsc2026-ec2-terminate-alert wsc2026-sg-remediation wsc2026-tag-alert; do aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text; done
# task.md 전용 함수 2개 (수동 채점 대비)
for fn in wsc2026-role-remediation wsc2026-ec2-type-remediation; do aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text; done
# 3-2 EventBridge 타깃
for rule in wsc2026-ec2-stop-rule wsc2026-ec2-terminate-rule; do echo "$rule -> $(aws events list-targets-by-rule --rule $rule --query "Targets[0].Arn" --output text)"; done
# 3-3 Config 룰 ACTIVE
aws configservice describe-config-rules --config-rule-names wsc2026-sg-ssh-rule wsc2026-required-tags-rule --query "ConfigRules[*].[ConfigRuleName,ConfigRuleState]" --output text
# 3-4 복구 테스트
aws ec2 stop-instances --instance-ids $INSTANCE_ID &>/dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 &>/dev/null
sleep 90
echo "EC2 State (expect running): $(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].State.Name" --output text)"
echo "SG Inbound Count (expect 0): $(aws ec2 describe-security-groups --group-ids $SG_ID --query "SecurityGroups[0].IpPermissions | length(@)" --output text)"
# 3-5 태그 컴플라이언스 (expect None)
aws configservice get-compliance-details-by-config-rule --config-rule-name wsc2026-required-tags-rule --compliance-types NON_COMPLIANT --query "EvaluationResults[0].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId" --output text
```

task.md 전용 시나리오 수동 시연 (role/type 변경 복구):

```bash
# 역할 변경 → 원복 확인 (다른 프로파일을 하나 만들어 교체해 본다)
ASSOC_ID=$(aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$INSTANCE_ID" --query "IamInstanceProfileAssociations[0].AssociationId" --output text)
aws ec2 replace-iam-instance-profile-association --association-id $ASSOC_ID --iam-instance-profile Name=<다른-프로파일>
sleep 90; aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$INSTANCE_ID" --query "IamInstanceProfileAssociations[0].IamInstanceProfile.Arn" --output text   # ...instance-profile/wsc2026-event-ec2-role

# 타입 변경 → 원복 확인. 반드시 stop 룰을 먼저 비활성화 (아래 '함정' 참고)
aws events disable-rule --name wsc2026-ec2-stop-rule
aws ec2 stop-instances --instance-ids $INSTANCE_ID && aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --instance-type t3.small
aws ec2 start-instances --instance-ids $INSTANCE_ID
sleep 180; aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].[InstanceType,State.Name]" --output text   # t3.micro running
aws events enable-rule --name wsc2026-ec2-stop-rule
```

