# Module 3 — Cloud Event Handling (ap-southeast-1)

보호 SG 에 Inbound 추가 시 CloudTrail→EventBridge→Lambda(지급 `remediate_security_group.py`)가 복구하고 SNS 로 알린다. 채점은 CloudShell 에서 `mark/mark2-3.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다 (CloudShell 단계는 공통).

## 디렉토리 구조

```
module-3-event-handling/
├── terraform/
│   ├── vpc.tf           # VPC(10.73/16) + 서브넷 1 + EC2 (IGW 없음 — 외부 접근 무요구)
│   ├── sg.tf            # protected SG (ingress 0개 + egress all)
│   ├── sns.tf           # alert topic
│   ├── lambda.tf        # 지급 py zip + 로그 그룹 + role/policy + function(env 2개)
│   ├── cloudtrail.tf    # trail + S3 버킷/정책
│   ├── eventbridge.tf   # rule + target + lambda permission
│   └── {versions,variables,outputs}.tf
├── README.md
└── README.linux.md

# 앱 소스: task-2/provided/module-3/remediate_security_group.py (제공 원본, 수정 금지) — terraform 이 직접 참조
# 채점: task-2/mark/mark2-3.sh (CloudShell, ap-southeast-1)
```

## 0. IAM 권한 프로브 (대회 시작 직후 1회)

[module-4 런북 0단계](../module-4-sqs-scaling/README.md)에서 1회만 수행한다.

## 1. 배포

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

## 2. 환경변수 (.env)

```powershell
$env:AWS_DEFAULT_REGION = "ap-southeast-1"
$env:PROTECTED_SG_ID    = terraform -chdir=terraform output -raw protected_sg_id
$env:TOPIC_ARN          = terraform -chdir=terraform output -raw topic_arn

@"
`$env:AWS_DEFAULT_REGION = "ap-southeast-1"
`$env:PROTECTED_SG_ID    = "$env:PROTECTED_SG_ID"
`$env:TOPIC_ARN          = "$env:TOPIC_ARN"
"@ | Set-Content .env.ps1

. .\.env.ps1   # 재접속 시: module-3-event-handling 디렉터리에서 `. .\.env.ps1` 만 다시 실행
```

## 3. 검증 1 — Lambda 직접 호출 (채점 3-5 와 동일 payload)

```powershell
'{"detail":{"eventName":"AuthorizeSecurityGroupIngress","requestParameters":{"groupId":"' + $env:PROTECTED_SG_ID + '"}}}' |
  Set-Content -NoNewline payload.json
aws ec2 authorize-security-group-ingress --group-id $env:PROTECTED_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws lambda invoke --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file://payload.json out.json
Get-Content out.json
# → "status": "RESTORED", "revokedPermissionCount": 1, "publishStatus": "SNS_PUBLISHED"
aws ec2 describe-security-groups --group-ids $env:PROTECTED_SG_ID --query "SecurityGroups[0].IpPermissions"
# → []
Remove-Item payload.json, out.json
```

## 4. 검증 2 — 실경로 (CloudTrail→EventBridge→Lambda — 실측 ~20초, 최대 수 분)

```powershell
aws ec2 authorize-security-group-ingress --group-id $env:PROTECTED_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
while ((aws ec2 describe-security-groups --group-ids $env:PROTECTED_SG_ID --query "length(SecurityGroups[0].IpPermissions)" --output text) -ne "0") { Start-Sleep 15 }
aws ec2 describe-security-groups --group-ids $env:PROTECTED_SG_ID --query "SecurityGroups[0].IpPermissions"
# → [] (복구 완료 — 180초 이내여야 함, 유의사항 10)
```

## 5. 제출 전 최종 확인

```powershell
aws ec2 describe-security-groups --group-ids $env:PROTECTED_SG_ID --query "SecurityGroups[0].IpPermissions"
# → [] (채점 3-2: Inbound 0개)
aws cloudtrail get-trail-status --name skills-ceh-cloudtrail --query IsLogging
# → true
```

### [CloudShell] 셀프 채점

```bash
# mark/mark2-3.sh 를 CloudShell 에 업로드(작업 → 파일 업로드) 후 실행. 저장소가 private 이라 git clone 은 쓰지 않는다.
# Windows 업로드 시 CRLF 가드 (멱등):
sed -i 's/\r$//' mark2-3.sh
bash mark2-3.sh
```

## 6. Teardown

```powershell
terraform -chdir=terraform destroy -auto-approve
```
