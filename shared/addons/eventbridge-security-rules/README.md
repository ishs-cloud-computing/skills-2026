# EventBridge 보안 룰 부착 KIT

보안 이벤트 룰(루트 로그인·IAM 변경·SG 인바운드·EC2 변경/상태·EBS 생성·GuardDuty·스케줄) + SNS 또는 Lambda 타깃 + (선택) GuardDuty detector · AWS Config recorder·관리형 룰·SSM 자동 복구.

## 이 KIT이 맞나

- 과제지에 **"보안 이벤트 감지·통지"·"EventBridge 규칙"·"GuardDuty"·"Config 규칙"** → 맞다.
- **메트릭 임계값 알람** → [cw-alarms](../cw-alarms/README.md).
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 현재 상태 — 먼저 봐야 할 전제

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| EventBridge 룰 | **없음** | **없음** | **없음** |
| SNS 토픽 | **없음** | **없음** | **없음** |
| **CloudTrail** | **없음** | **없음** | **없음** |
| GuardDuty | **없음** | **없음** | **없음** |
| AWS Config | **없음** | **없음** | **없음** |
| `use1` provider alias | **없음** | 있음 (`providers.tf`) | 있음 (`versions.tf`) |

**`AWS API Call via CloudTrail` 패턴(root_login·iam_change·sg_ingress·ec2_modify)은 활성 Trail이 없으면 절대 발화하지 않는다.** 세 세트 모두 Trail이 없으므로 [cloudtrail-hardening](../cloudtrail-hardening/README.md) 을 먼저 얹어야 한다. State-change·EBS·GuardDuty·스케줄 룰은 Trail이 필요 없다.

## 복사할 파일

| 원본 | 언제 | 내용 |
| --- | --- | --- |
| `eventbridge.tf` | 항상 | 룰 패턴 locals(키 7개) · SNS 토픽(+email·토픽 정책) · 룰(for_each) · 스케줄 룰 · 타깃 |
| `lambda.tf` + `lambda/alert/index.py` | `addon_evb_target_type = "lambda"` 일 때만 | 알림 Lambda · 실행 Role · `aws_lambda_permission`(룰별) |
| `guardduty.tf` | GuardDuty 요구 시만 | `aws_guardduty_detector` |
| `config.tf` | Config 요구 시만 | 딜리버리 버킷+정책 · recorder Role · recorder/channel/status · 관리형 룰 · SSM 복구 |
| `variables.tf` | 항상 | `addon_evb_*` 변수 |

**과제에 없는 파일은 지운다** — 불필요 리소스 감점 대상이다.

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_evb_rules` | map | key(패턴 키) → **룰 이름(과제지 명시값)**. 키: `root_login` `iam_change` `sg_ingress` `ec2_modify` `ec2_state` `ebs_create` `guardduty` |
| `addon_evb_schedule_rules` | `{}` | 룰 이름 → `rate(5 minutes)` / `cron(0 9 * * ? *)` |
| `addon_evb_ec2_states` | `["stopped","terminated"]` | `ec2_state` 룰이 잡을 상태 |
| `addon_evb_guardduty_min_severity` | `4` | 4=Medium 7=High |
| `addon_evb_target_type` | `"sns"` | `sns` 또는 `lambda` |
| `addon_evb_sns_topic_name` | `"security-alert-topic"` | 과제지 명시 이름과 정확히 일치 |
| `addon_evb_email` | `""` | 빈 문자열이면 구독 안 만든다 |
| `addon_evb_lambda_name` / `_runtime` | `"security-alert-handler"` / `"python3.12"` | 과제지 명시 버전과 정확히 일치 |
| `addon_evb_guardduty_enabled` | `false` | **리전당 1개** — 이미 켜져 있으면 false |
| `addon_evb_config_enabled` | `false` | **리전당 recorder 1개** |
| `addon_evb_config_bucket_prefix` / `_role_name` | `"config-logs"` / `"config-recorder-role"` | |
| `addon_evb_config_resource_types` | `["AWS::EC2::Instance","AWS::EC2::SecurityGroup"]` | 빈 목록이면 all_supported |
| `addon_evb_config_rules` | map | 관리형 룰. 필요한 것만 |
| `addon_evb_remediation_rule_key` | `""` | SSM 복구를 붙일 Config 룰 key |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## 0. 전제 확인 — Trail이 살아 있나

```powershell
aws cloudtrail describe-trails --query "trailList[].[Name,IsMultiRegionTrail,IncludeGlobalServiceEvents]" --output table
aws cloudtrail get-trail-status --name <Trail> --query IsLogging
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 Trail이 **없다.** API Call 패턴을 쓰려면 먼저 [cloudtrail-hardening](../cloudtrail-hardening/README.md) 을 얹는다:

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_trail_name                  = "skills-trail"
addon_trail_multi_region          = true    # IAM/ConsoleLogin 을 다른 리전 룰로 받으려면 필요
addon_trail_include_global_events = true
```

```powershell
terraform output -raw trail_name
aws cloudtrail get-trail-status --name (terraform output -raw trail_name) --query "[IsLogging,LatestDeliveryTime]"
```

IAM·ConsoleLogin은 **글로벌 서비스 이벤트**다 — us-east-1에 Trail이 있거나 `include_global_service_events = true` 여야 다른 리전 룰로 전달된다. `root_login`·`iam_change` 룰은 **us-east-1에 만드는 게 가장 확실**하다(`provider = aws.use1`). set-03·set-07은 alias가 이미 있고, set-02는 `versions.tf` 에 추가해야 한다.
</details>

## 1. 룰 + SNS 타깃

```hcl
# 파일: set-XX/task-1/terraform/eventbridge.tf   (KIT에서 복사됨)
resource "aws_cloudwatch_event_rule" "addon_evb" {
  for_each      = var.addon_evb_rules
  name          = each.value                                    # 과제지 명시 이름
  event_pattern = jsonencode(local.addon_evb_patterns[each.key])
}

resource "aws_cloudwatch_event_target" "addon_evb" {
  for_each  = var.addon_evb_rules
  rule      = aws_cloudwatch_event_rule.addon_evb[each.key].name
  target_id = "addon-target"
  arn       = local.addon_evb_target_arn
}
```

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_evb_rules = {
  sg_ingress = "skills-sg-ingress-rule"
  ec2_state  = "skills-ec2-state-rule"
  guardduty  = "skills-guardduty-rule"
}
addon_evb_ec2_states     = ["stopped", "terminated"]
addon_evb_target_type    = "sns"
addon_evb_sns_topic_name = "skills-security-topic"
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "evb_topic_arn"  { value = aws_sns_topic.addon_evb.arn }
output "evb_rule_names" { value = { for k, v in aws_cloudwatch_event_rule.addon_evb : k => v.name } }
```

```powershell
terraform output -raw evb_topic_arn
terraform output -json evb_rule_names

aws events list-rules --name-prefix skills- --query "Rules[].[Name,State]" --output table
aws events list-targets-by-rule --rule (terraform output -json evb_rule_names | ConvertFrom-Json).sg_ingress
aws sns list-subscriptions-by-topic --topic-arn (terraform output -raw evb_topic_arn)

# 발화 테스트 (sg_ingress) — 1~2분 내 통지
aws ec2 authorize-security-group-ingress --group-id <sg> --protocol tcp --port 8080 --cidr 10.0.0.0/16
```

테스트에 쓸 SG는 세트별로 output이 있다:

| 세트 | 만만한 SG output |
| --- | --- |
| set-02 | `environment_sg_id` · `node_sg_id` · `cluster_extra_sg_id` |
| set-03 | `mark_sg_id` · `alb_sg_id` · `eks_shared_node_sg_id` |
| set-07 | `mark_sg_id` · `eks_shared_node_sg_id` |

**채점 대상 SG로 테스트하지 않는다** — 룰을 추가하면 SG 채점이 깨진다. 임시 SG를 따로 만들어 쓰고 지운다.

**EventBridge → SNS 직접 타깃은 토픽 정책(`events.amazonaws.com` Publish)이 없으면 조용히 실패한다.** KIT이 만든다 — 기존 토픽 재사용 시 직접 추가한다.
</details>

## 2. Lambda 타깃

```hcl
# 파일: set-XX/task-1/terraform/lambda.tf   (KIT에서 복사됨)
resource "aws_lambda_permission" "addon_evb" {
  for_each      = var.addon_evb_rules
  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.addon_evb_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.addon_evb[each.key].arn
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "evb_lambda_name"      { value = aws_lambda_function.addon_evb_alert.function_name }
output "evb_lambda_log_group" { value = "/aws/lambda/${aws_lambda_function.addon_evb_alert.function_name}" }
```

```powershell
terraform output -raw evb_lambda_name
aws logs tail (terraform output -raw evb_lambda_log_group) --since 5m

# 채점이 이 정책 존재를 직접 확인하는 세트가 있다 (set-08 m3 3-4)
aws lambda get-policy --function-name (terraform output -raw evb_lambda_name) --query Policy --output text
```

**기존 Lambda를 타깃으로 쓰려면** `local.addon_evb_target_arn` 을 기존 함수 ARN으로 바꾸고 `aws_lambda_permission` 만 남긴다:

| 세트 | 기존 함수 |
| --- | --- |
| set-02 | `aws_lambda_function.book` |
| set-03 | `aws_lambda_function.book_get` |
| set-07 | `aws_lambda_function.get_booking` |

단 그 함수는 조회 API 핸들러라 이벤트 처리 코드가 없다 — **새 함수를 만드는 쪽이 맞다.**
</details>

## 3. 패턴 추가·한정

```hcl
# 파일: set-XX/task-1/terraform/eventbridge.tf
# local.addon_evb_patterns 안에 키를 추가하고 addon_evb_rules 에 이름을 넣는다
s3_public = {
  source      = ["aws.s3"]
  detail-type = ["AWS API Call via CloudTrail"]
  detail = {
    eventSource = ["s3.amazonaws.com"]
    eventName   = ["PutBucketAcl", "PutBucketPolicy", "DeleteBucketPublicAccessBlock"]
  }
}
```

아래 셋은 **블록이 아니라 조각**이다. 통째로 붙이지 말고 위 `detail = { ... }` 안에 필요한 줄만 넣는다.

```hcl
# 파일: set-XX/task-1/terraform/eventbridge.tf — sg_ingress 룰의 detail 안에
requestParameters = { groupId = ["<sg-id>"] }
```

```hcl
# 파일: set-XX/task-1/terraform/eventbridge.tf — ec2_state 룰의 detail 안에
"instance-id" = ["<i-id>"] # 키에 하이픈이 있어 따옴표가 필요하다
```

```hcl
# 파일: set-XX/task-1/terraform/eventbridge.tf — 원복 값 제외로 무한 루프 차단
requestParameters = { instanceType = { value = [{ anything-but = "t3.micro" }] } }
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```powershell
# 한정할 SG id 를 output 에서
terraform output -raw mark_sg_id            # set-03 / set-07
terraform output -raw environment_sg_id     # set-02

# 패턴이 실제 이벤트와 맞는지 (룰을 만들기 전에)
aws events test-event-pattern `
  --event-pattern (Get-Content pattern.json -Raw) `
  --event (Get-Content sample-event.json -Raw)
```

`s3_public` 패턴을 쓸 버킷:

```powershell
terraform output -raw s3_bucket_name        # 세 세트 모두 있음
```

GuardDuty 패턴의 `numeric` 비교(`[">=", 4]`)는 EventBridge 숫자 매칭 문법이다 — 문자열 `"4"` 로 쓰면 매칭되지 않는다.
</details>

## 4. GuardDuty detector

```hcl
# 파일: set-XX/task-1/terraform/guardduty.tf   (KIT에서 복사됨)
resource "aws_guardduty_detector" "addon" {
  count  = var.addon_evb_guardduty_enabled ? 1 : 0
  enable = true
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**리전당 1개다.** 이미 켜져 있는데 또 만들면 apply가 실패한다 — 먼저 확인:

```powershell
aws guardduty list-detectors --query DetectorIds
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "guardduty_detector_id" { value = aws_guardduty_detector.addon[0].id }
```

```powershell
terraform output -raw guardduty_detector_id
aws guardduty get-detector --detector-id (terraform output -raw guardduty_detector_id) `
  --query "[Status,FindingPublishingFrequency]"

# 샘플 findings 로 룰 발화 테스트
aws guardduty create-sample-findings --detector-id (terraform output -raw guardduty_detector_id) `
  --finding-types "UnauthorizedAccess:EC2/SSHBruteForce"
aws guardduty list-findings --detector-id (terraform output -raw guardduty_detector_id) --max-items 5
```

세 세트 모두 GuardDuty가 꺼져 있다.
</details>

## 5. AWS Config recorder + 관리형 룰

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_evb_config_enabled       = true
addon_evb_config_bucket_prefix = "skills-config-logs"
addon_evb_config_role_name     = "skills-config-role"
addon_evb_config_resource_types = ["AWS::EC2::Instance", "AWS::EC2::SecurityGroup"]
addon_evb_config_rules = {
  ssh  = { name = "skills-ssh-disabled", source_identifier = "INCOMING_SSH_DISABLED", resource_types = ["AWS::EC2::SecurityGroup"] }
  tags = { name = "skills-required-tags", source_identifier = "REQUIRED_TAGS", input_parameters = { tag1Key = "Project" }, resource_types = ["AWS::EC2::Instance"] }
}
addon_evb_remediation_rule_key = ""       # "ssh" 면 SSM 자동 복구 부착
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**recorder도 리전당 1개다:**

```powershell
aws configservice describe-configuration-recorders --query "ConfigurationRecorders[].name"
aws configservice describe-configuration-recorder-status --query "ConfigurationRecordersStatus[].[name,recording,lastStatus]"
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "config_bucket"     { value = aws_s3_bucket.addon_evb_config[0].id }
output "config_rule_names" { value = { for k, v in aws_config_config_rule.addon : k => v.name } }
```

```powershell
terraform output -json config_rule_names
$r = (terraform output -json config_rule_names | ConvertFrom-Json).ssh

aws configservice describe-compliance-by-config-rule --config-rule-names $r `
  --query "ComplianceByConfigRules[].[ConfigRuleName,Compliance.ComplianceType]" --output table

# 평가는 recorder ON 뒤 수 분 — 강제로 돌린다
aws configservice start-config-rules-evaluation --config-rule-names $r

# 어느 리소스가 NON_COMPLIANT 인지
aws configservice get-compliance-details-by-config-rule --config-rule-name $r `
  --compliance-types NON_COMPLIANT --query "EvaluationResults[].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId"
```

**recorder 스코프를 넓히면 태그 없는 관리형 리소스가 `REQUIRED_TAGS` NON_COMPLIANT를 만든다.** "NON_COMPLIANT 0건"을 채점하는 문항이 있으므로 기본값(EC2 Instance + SecurityGroup)을 유지한다.

세 세트 task-1에는 EC2 인스턴스가 거의 없다 — set-03의 `aws_instance.bastion` 하나뿐이고 set-02·set-07은 EKS 노드(태그가 EKS가 붙인 것)뿐이다. `REQUIRED_TAGS` 를 쓰면 노드가 전부 NON_COMPLIANT가 될 수 있다:

```powershell
aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Project'].Value|[0]]" --output table
```
</details>

<details><summary><b>SSM 자동 복구 (선택)</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/config.tf
resource "aws_config_remediation_configuration" "addon" {
  count            = var.addon_evb_remediation_rule_key == "" ? 0 : 1
  config_rule_name = aws_config_config_rule.addon[var.addon_evb_remediation_rule_key].name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisablePublicAccessForSecurityGroup"
  resource_type    = "AWS::EC2::SecurityGroup"
  automatic        = true

  parameter {
    name         = "GroupId"
    resource_value = "RESOURCE_ID"
  }
  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.addon_evb_remediation[0].arn
  }
}
```

```powershell
# 문서의 파라미터 이름을 먼저 확인한다
aws ssm describe-document --name AWS-DisablePublicAccessForSecurityGroup `
  --query "Document.Parameters[].[Name,Type]" --output table

aws configservice describe-remediation-configurations --config-rule-names <룰이름>
aws ssm describe-automation-executions --max-results 5 `
  --query "AutomationExecutionMetadataList[].[DocumentName,AutomationExecutionStatus]"
```

`AutomationAssumeRole` 이 없으면 복구가 **조용히 실패**한다. 다른 룰에 붙이려면 `resource_type`·`target_id`·`parameter` 를 그 문서에 맞춘다.
</details>

## VERIFY

```powershell
aws events list-rules --name-prefix skills- --query "Rules[].[Name,State]" --output table
aws events list-targets-by-rule --rule <룰이름>
aws sns list-subscriptions-by-topic --topic-arn (terraform output -raw evb_topic_arn)
aws logs tail (terraform output -raw evb_lambda_log_group) --since 5m    # lambda 타깃일 때
```

## TROUBLESHOOT

- 룰 `name` 변경은 **재생성**(이름이 식별자), 패턴·타깃은 in-place다.
- **`AWS API Call via CloudTrail` 패턴은 활성 Trail이 없으면 절대 발화하지 않는다.**
- IAM·ConsoleLogin은 글로벌 이벤트다 — us-east-1 Trail 또는 `include_global_service_events = true`.
- EventBridge → SNS 직접 타깃은 **토픽 정책**이 없으면 조용히 실패한다.
- Lambda 타깃은 `aws_lambda_permission` 이 없으면 Invoke를 못 한다 — 채점이 `lambda get-policy` 로 확인하는 세트가 있다.
- GuardDuty detector·Config recorder는 **리전당 1개**. 이미 있으면 변수를 false로 두고 룰만 쓴다.
- Config recorder 스코프를 넓히면 NON_COMPLIANT가 늘어난다.
- Config 룰 평가는 수 분 걸린다 — `start-config-rules-evaluation` 으로 강제한다.
- SSM 복구는 `AutomationAssumeRole` 이 없으면 조용히 실패한다.
- email 구독은 `Confirmed` 여야 통지가 간다.
- GuardDuty 패턴의 `numeric` 비교는 숫자로 쓴다 — 문자열이면 매칭되지 않는다.

## 실전 구현 (참고용)

- set-02 task-2 module-3-event(RC 판에서 삭제 — git 이력) `terraform/eventbridge.tf`(룰 6종 + Lambda 타깃·permission) · `terraform/config.tf`(recorder + `INCOMING_SSH_DISABLED`·`REQUIRED_TAGS`) · `terraform/lambda/tag_alert/index.py`
- set-08 task-2 module-3-event-handling `terraform/eventbridge.tf`(AuthorizeSecurityGroupIngress → Lambda) · `terraform/sns.tf`

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
