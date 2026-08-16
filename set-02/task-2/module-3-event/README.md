# module-3-event — Cloud Event Handling (eu-west-1)

EC2 정책 위반(SG 인바운드 추가·역할 변경·중지·종료·타입 변경)을 EventBridge로 감지해 Lambda가 자동 복구하거나 SNS로 알리고, AWS Config가 SSH 인바운드·필수 태그를 상시 감시한다.

```
module-3-event/
└── terraform/
    ├── vpc.tf ec2.tf sns.tf iam.tf
    ├── cloudtrail.tf                # 트레일 + CloudTrail·Config 공용 로그 버킷
    ├── lambda.tf eventbridge.tf     # 함수 6개 + 룰 6개 (task ∪ mark 합집합)
    ├── config.tf                    # 레코더 + sg-ssh / required-tags 룰
    └── lambda/<function>/index.py   # provided 스켈레톤 TODO 완성본
```

## 배포 (본 PC, PowerShell)

**먼저 `terraform.tfvars` 의 `player_number` 를 본인 비번호로 바꾼다.** apply 는 tfvars 를 자동으로 읽으므로 `-var` 를 붙이지 않는다.

```powershell
cd module-3-event\terraform
terraform init
terraform apply
terraform output -json > outputs.json
```

apply 후 Config 첫 평가와 CloudTrail 이벤트 전달 활성화까지 **5~10분 대기** 후 채점한다.

```powershell
# Config 첫 평가 강제 트리거 (3-5 를 바로 확인하고 싶을 때)
$env:AWS_DEFAULT_REGION = "eu-west-1"
aws configservice start-config-rules-evaluation --config-rule-names wsc2026-required-tags-rule wsc2026-sg-ssh-rule
```

## 리소스 검증 (본 PC, PowerShell)

```powershell
$env:AWS_DEFAULT_REGION = "eu-west-1"
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$INSTANCE_ID = aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-event-ec2" "Name=instance-state-name,Values=running,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text
$SG_ID = aws ec2 describe-security-groups --filters "Name=group-name,Values=wsc2026-event-sg" --query "SecurityGroups[0].GroupId" --output text

# 3-1 SNS + Lambda (runtime python3.12)
aws sns get-topic-attributes --topic-arn "arn:aws:sns:eu-west-1:${ACCOUNT_ID}:wsc2026-event-alert" --query "Attributes.TopicArn" --output text
foreach ($fn in "wsc2026-ec2-stop-remediation","wsc2026-ec2-terminate-alert","wsc2026-sg-remediation","wsc2026-tag-alert") { aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text }
# 3-2 EventBridge 타깃
foreach ($rule in "wsc2026-ec2-stop-rule","wsc2026-ec2-terminate-rule") { "$rule -> $(aws events list-targets-by-rule --rule $rule --query 'Targets[0].Arn' --output text)" }
# 3-3 Config 룰 ACTIVE
aws configservice describe-config-rules --config-rule-names wsc2026-sg-ssh-rule wsc2026-required-tags-rule --query "ConfigRules[*].[ConfigRuleName,ConfigRuleState]" --output text
# 3-4 복구 테스트: 중지 + SSH 인바운드 추가 → 복구 확인
aws ec2 stop-instances --instance-ids $INSTANCE_ID | Out-Null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 | Out-Null
Start-Sleep 90
"EC2 State (expect running): $(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text)"
"SG Inbound Count (expect 0): $(aws ec2 describe-security-groups --group-ids $SG_ID --query 'SecurityGroups[0].IpPermissions | length(@)' --output text)"
# 3-5 태그 컴플라이언스 (expect None)
aws configservice get-compliance-details-by-config-rule --config-rule-name wsc2026-required-tags-rule --compliance-types NON_COMPLIANT --query "EvaluationResults[0].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId" --output text
```
## Linux 런북

개인 리눅스 로컬 전용 절차는 [README.linux.md](README.linux.md) 로 분리했다. 대회 본 PC 에서는 위 PowerShell 런북을 쓴다.

## 요구사항 ↔ 구현 매핑

| 항목 | 요구 | 구현 |
|---|---|---|
| task 1. VPC | event-vpc 172.16.0.0/16, pub-a/b, event-pub-rtb, event-igw | `vpc.tf` (`variables.tf` subnets 맵) |
| task 2. EC2 | wsc2026-event-ec2 t3.micro, event-pub-a, wsc2026-event-ec2-role | `ec2.tf` |
| task 3. SG | wsc2026-event-sg 최소 구성 | `ec2.tf` (인바운드 0개 기준선) |
| task 4. EventBridge | sg-change / role-change / ec2-terminate / ec2-type-change | `eventbridge.tf` |
| task 5. CloudTrail | wsc2026-event-trail, Management R/W | `cloudtrail.tf` |
| task 6. Lambda | 4개 함수 + wsc2026-event-lambda-role (lambda.md 스펙) | `lambda.tf` + `lambda/*/index.py` + `iam.tf` |
| task 7. SNS | wsc2026-event-alert | `sns.tf` |
| mark 3-1 | 함수 4개(stop/terminate/sg/tag) python3.12 + Topic ARN | `lambda.tf` (`function_names`) |
| mark 3-2 | ec2-stop-rule → stop-remediation, ec2-terminate-rule → terminate-alert | `eventbridge.tf` (`rule_targets`) |
| mark 3-3 | wsc2026-sg-ssh-rule / wsc2026-required-tags-rule ACTIVE | `config.tf` |
| mark 3-4 | stop→running 복구, SSH 인바운드→0개 복구 | `lambda/ec2_stop_remediation` + `lambda/sg_remediation` |
| mark 3-5 | required-tags NON_COMPLIANT 0건 | `config.tf` 스코프(EC2 Instance) + provider default_tags(Project) |

## 설계 근거 · 함정

- **task.md와 mark2-3.sh의 리소스가 불일치 → 합집합 구현.** task.md/lambda.md는 sg/role/terminate/type 4개 함수·4개 룰을, 채점 스크립트는 stop/terminate/sg/tag 4개 함수·stop/terminate 룰·Config 룰 2개를 요구한다. 채점 스크립트가 1순위(작업규칙 4)지만 task.md 항목은 수동 채점 가능성이 있어 **함수 6개·룰 6개** 전부 만든다.
- **stop 복구는 `stopping` 상태에서 트리거** — mark 3-4는 stop 후 (3-1~3-3 수행 + sleep 30) 시점에 `running`을 기대한다. `stopped`를 기다렸다 시작하면 늦다. 네이티브 State-change 이벤트(수 초)로 받고 waiter(5초 간격)로 stopped 직후 start.
- **SG 복구는 CloudTrail→EventBridge 경로라 전달 지연(보통 수십 초~1분)이 있다.** SG 규칙 변경엔 네이티브 이벤트가 없다. 채점 첫 시도에서 SG Inbound가 1이면 잠시 후 3-4 블록만 재실행. **apply 직후엔 트레일 활성화까지 몇 분 걸리므로 배포 직후 바로 테스트하지 말 것.**
- **type-remediation 시연 전 `wsc2026-ec2-stop-rule` 비활성화 필수** — 타입 원복 절차(stop→modify→start)의 stop이 stop-remediation과 레이스해 modify가 `IncorrectInstanceState`로 실패한다. 시연 후 재활성화.
- **무한 루프 차단 2중 장치**: type-change 룰은 `anything-but: t3.micro`로 원복 이벤트를 제외하고, 람다도 값 비교로 스킵. role-remediation은 현재 프로파일이 원본이면 즉시 return.
- **Config 스코프는 EC2 Instance·SecurityGroup만 기록** — 스코프를 넓히면 태그 없는 관리형 리소스가 3-5(NON_COMPLIANT=None)를 깨뜨린다. required-tags는 `Project` 키를 검사하고 provider `default_tags`가 인스턴스에 항상 부착한다. 첫 평가는 몇 분 걸리므로 필요 시 `start-config-rules-evaluation`.
- **인스턴스 프로파일 이름 = 역할 이름(wsc2026-event-ec2-role)** — role-remediation이 `ROLE_NAME`을 프로파일 Name으로 사용해 원복한다. 프로파일 이름에 `-profile` 접미사를 붙이면 복구가 깨진다.
- **Bastion 없음** — mark2-3.sh는 CloudShell 실행 전제고 모든 채점이 AWS API 호출이라 VPC 내부 접근이 불필요하다. EC2 접속은 SSM.
- EC2 `lifecycle.ignore_changes = [instance_type]` — 타입 변경 시연 후 `terraform plan`에 diff가 남지 않게 한다.
