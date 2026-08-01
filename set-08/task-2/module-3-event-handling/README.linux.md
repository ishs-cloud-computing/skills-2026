# Module 3 — Cloud Event Handling (ap-southeast-1) — Linux 런북

PowerShell 대신 bash/zsh 용. 단계 구성은 [README.md](README.md) 와 1:1.

## 0. IAM 권한 프로브

[module-4 런북 0단계](../module-4-sqs-scaling/README.linux.md)에서 1회만 수행한다.

## 1. 배포

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

## 2. 환경변수 (.env)

```bash
export AWS_DEFAULT_REGION="ap-southeast-1"
export PROTECTED_SG_ID="$(terraform -chdir=terraform output -raw protected_sg_id)"
export TOPIC_ARN="$(terraform -chdir=terraform output -raw topic_arn)"

cat > .env <<EOF
export AWS_DEFAULT_REGION="ap-southeast-1"
export PROTECTED_SG_ID="${PROTECTED_SG_ID}"
export TOPIC_ARN="${TOPIC_ARN}"
EOF

source .env   # 재접속 시: module-3-event-handling 디렉터리에서 `source .env` 만 다시 실행
```

## 3. 검증 1 — Lambda 직접 호출 (채점 3-5 와 동일 payload)

```bash
jq -n --arg sg "$PROTECTED_SG_ID" '{detail:{eventName:"AuthorizeSecurityGroupIngress",requestParameters:{groupId:$sg}}}' > payload.json
aws ec2 authorize-security-group-ingress --group-id "$PROTECTED_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
aws lambda invoke --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file://payload.json out.json
cat out.json
# → "status": "RESTORED", "revokedPermissionCount": 1, "publishStatus": "SNS_PUBLISHED"
aws ec2 describe-security-groups --group-ids "$PROTECTED_SG_ID" --query "SecurityGroups[0].IpPermissions"
# → []
rm -f payload.json out.json
```

## 4. 검증 2 — 실경로 (CloudTrail→EventBridge→Lambda, 이벤트 전달까지 수 분)

```bash
aws ec2 authorize-security-group-ingress --group-id "$PROTECTED_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
until [ "$(aws ec2 describe-security-groups --group-ids "$PROTECTED_SG_ID" --query 'length(SecurityGroups[0].IpPermissions)' --output text)" = "0" ]; do sleep 15; done
aws ec2 describe-security-groups --group-ids "$PROTECTED_SG_ID" --query "SecurityGroups[0].IpPermissions"
# → [] (복구 완료 — 180초 이내여야 함, 유의사항 10)
```

## 5. 제출 전 최종 확인

```bash
aws ec2 describe-security-groups --group-ids "$PROTECTED_SG_ID" --query "SecurityGroups[0].IpPermissions"
# → [] (채점 3-2: Inbound 0개)
aws cloudtrail get-trail-status --name skills-ceh-cloudtrail --query IsLogging
# → true
```

### [CloudShell] 셀프 채점

```bash
sed -i 's/\r$//' mark/mark2-3.sh
bash mark/mark2-3.sh
```

## 6. Teardown

```bash
terraform -chdir=terraform destroy -auto-approve
```
