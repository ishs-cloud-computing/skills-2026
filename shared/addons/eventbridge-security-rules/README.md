# eventbridge-security-rules 부착 스니펫

EventBridge 보안 룰 패턴 모음(루트 로그인·IAM 변경·SG 인바운드·EC2 변경/상태·EBS 생성·GuardDuty·스케줄)
+ SNS 직접 타깃 또는 공통 Lambda 알림 핸들러 + (선택) GuardDuty detector + (선택) AWS Config recorder·관리형 룰·SSM 자동 복구.
2과제 이벤트 모듈(set-02 m3, set-08 m3)과 1과제 Security 옵션("보안 이벤트 감지·통지") 추가 문항에 대응한다.

## RUN guard

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체를 `init`/`apply` 하지 않으므로 기존 Kit의 state를 건드리지 않는다.

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

- **VERIFY** = 이 README의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 이 README에는 이 KIT 고유 문제만 둔다.

## 파일

- `eventbridge.tf` — 룰 패턴 locals(키 7개) · SNS 토픽(+email, 토픽 정책) · 룰(for_each, 과제지 이름 주입) · 스케줄 룰 · 타깃
- `lambda.tf` — `addon_evb_target_type = "lambda"` 일 때만: 알림 Lambda · 실행 Role(Basic + sns:Publish) · `aws_lambda_permission`(룰별)
- `lambda/alert/index.py` — 이벤트를 SNS 로 발행하는 공통 핸들러 (`index.handler`)
- `guardduty.tf` — `aws_guardduty_detector` (선택)
- `config.tf` — Config 딜리버리 버킷+정책 · recorder Role · recorder/channel/status · 관리형 룰(for_each) · SSM 자동 복구 예시(선택)
- `variables.tf` — `addon_evb_*` 변수. 룰·토픽·Config 룰 이름은 과제지 명시값으로 tfvars 에서 덮어쓴다

## 부착 절차

1. 키트 전체(`*.tf` + `lambda/`)를 `set-XX/task-Y/terraform/` 으로 복사한다. Lambda 타깃을 안 쓰면 `lambda.tf`·`lambda/` 는 빼도 된다(`addon_evb_target_type = "sns"` 유지). Config·GuardDuty 가 과제에 없으면 `config.tf`·`guardduty.tf` 와 해당 변수를 지운다(불필요 리소스 감점).
2. `terraform.tfvars` 에 값을 넣는다. 기존 Lambda 를 타깃으로 쓰려면 `eventbridge.tf` 의 `local.addon_evb_target_arn` 을 `aws_lambda_function.<기존>.arn` 으로 바꾸고 `lambda.tf` 의 `aws_lambda_permission` 만 남긴다.

   ```hcl
   # 룰 — 필요한 키만 남기고 값은 과제지 룰 이름
   addon_evb_rules = {
     root_login = "skills-root-login-rule"
     iam_change = "skills-iam-change-rule"
     sg_ingress = "skills-sg-ingress-rule"
     ec2_modify = "skills-ec2-modify-rule"
     ec2_state  = "skills-ec2-state-rule"
     ebs_create = "skills-ebs-create-rule"
     guardduty  = "skills-guardduty-rule"
   }
   addon_evb_ec2_states     = ["stopped", "terminated"]
   addon_evb_schedule_rules = { "skills-daily-audit" = "cron(0 0 * * ? *)" }   # 필요 시

   # 타깃
   addon_evb_target_type    = "sns"                 # 또는 "lambda"
   addon_evb_sns_topic_name = "skills-security-topic"
   addon_evb_email          = ""                    # 과제지가 요구할 때만
   addon_evb_lambda_name    = "skills-security-handler"
   addon_evb_lambda_runtime = "python3.12"

   # GuardDuty / Config — 과제지가 요구할 때만
   addon_evb_guardduty_enabled = false
   addon_evb_config_enabled    = false
   addon_evb_config_bucket_prefix = "skills-config-logs"
   addon_evb_config_role_name     = "skills-config-role"
   addon_evb_config_rules = {
     ssh  = { name = "skills-ssh-disabled", source_identifier = "INCOMING_SSH_DISABLED", resource_types = ["AWS::EC2::SecurityGroup"] }
     tags = { name = "skills-required-tags", source_identifier = "REQUIRED_TAGS", input_parameters = { tag1Key = "Project" }, resource_types = ["AWS::EC2::Instance"] }
   }
   addon_evb_remediation_rule_key = ""             # "ssh" 면 SSM 자동 복구 부착
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws events list-rules --name-prefix skills- --query 'Rules[].[Name,State]' --output table
   aws events list-targets-by-rule --rule skills-sg-ingress-rule
   aws sns list-subscriptions-by-topic --topic-arn <토픽ARN>
   # 발화 테스트 (sg_ingress): 테스트 SG 에 인바운드 한 줄 추가 → 1~2분 내 SNS/Lambda 로그
   aws ec2 authorize-security-group-ingress --group-id <sg> --protocol tcp --port 8080 --cidr 10.0.0.0/16
   aws logs tail /aws/lambda/skills-security-handler --since 5m      # lambda 타깃일 때
   aws configservice describe-compliance-by-config-rule --config-rule-names skills-ssh-disabled   # Config
   ```

## 블록

### 패턴 추가 (키트에 없는 이벤트)

`eventbridge.tf` 의 `local.addon_evb_patterns` 에 키를 추가하고 `addon_evb_rules` 에 이름을 넣는다.

```hcl
# local.addon_evb_patterns 안에:
s3_public = {
  source      = ["aws.s3"]
  detail-type = ["AWS API Call via CloudTrail"]
  detail = {
    eventSource = ["s3.amazonaws.com"]
    eventName   = ["PutBucketAcl", "PutBucketPolicy", "DeleteBucketPublicAccessBlock"]
  }
}
```

### 특정 인스턴스/SG 로 한정 (set-02 m3 형태)

```hcl
# 패턴 detail 안에:
requestParameters = { groupId = ["<sg-id>"] }          # sg_ingress
instance-id       = ["<i-id>"]                          # ec2_state
```

### 원복 값 제외로 무한 루프 차단 (복구 Lambda 가 ModifyInstanceAttribute 를 다시 부를 때)

```hcl
requestParameters = { instanceType = { value = [{ anything-but = "t3.micro" }] } }
```

### 기존 알람 SNS 토픽 재사용

`aws_sns_topic.addon_evb` 를 지우고 `local.addon_evb_target_arn` 의 토픽 ARN 을 `var.<기존 토픽 ARN>` 으로 바꾼다. 기존 토픽에도 `events.amazonaws.com` Publish 허용 토픽 정책이 **필수**.

## 함정

- 전부 신규 리소스 — 기존 리소스 재생성 없음. 룰 `name` 변경은 ⚠ 재생성(이름이 식별자), 패턴·타깃은 in-place.
- **`AWS API Call via CloudTrail` 패턴(root_login·iam_change·sg_ingress·ec2_modify)은 해당 리전에 management 이벤트를 기록 중인 활성 Trail 이 없으면 절대 발화하지 않는다.** cloudtrail-hardening 키트 또는 기존 Trail 확인(`aws cloudtrail describe-trails`, `get-trail-status` → `IsLogging=true`). State-change·EBS·GuardDuty·스케줄은 Trail 불필요.
- IAM·ConsoleLogin 은 글로벌 서비스 이벤트 — **us-east-1 에 Trail 이 있거나 Trail 의 `include_global_service_events = true`** 여야 다른 리전 룰로 전달된다. root_login/iam_change 룰은 us-east-1 에 만드는 게 가장 확실(provider alias 필요 — versions.tf 에 `use1` 추가).
- EventBridge → SNS 직접 타깃은 **토픽 정책**(`events.amazonaws.com` Publish) 이 없으면 조용히 실패한다. 스니펫이 만든다 — 기존 토픽 재사용 시 직접 추가.
- Lambda 타깃은 `aws_lambda_permission` 이 없으면 룰이 Invoke 를 못 한다. set-08 m3 채점 3-4 는 `lambda get-policy` 로 이 정책 존재를 확인한다.
- `archive_file` 은 `hashicorp/archive` 프로바이더 — init 시 자동 설치된다. `build/` 디렉토리는 `.gitignore` 대상.
- GuardDuty detector·Config recorder 는 **리전당 1개**. 이미 있으면(`aws guardduty list-detectors`, `aws configservice describe-configuration-recorders`) 변수를 false 로 두고 룰만 쓴다 — 켜져 있는데 또 만들면 apply 실패.
- Config recorder 스코프를 넓히면 태그 없는 관리형 리소스가 REQUIRED_TAGS NON_COMPLIANT 를 만든다(set-02 m3 채점 3-5 "NON_COMPLIANT 0건"). 기본값은 EC2 Instance + SecurityGroup 만.
- Config 룰 평가는 recorder 가 ON 된 뒤 수 분 걸린다. `aws configservice start-config-rules-evaluation --config-rule-names <이름>` 로 강제.
- SSM 자동 복구 예시는 `AWS-DisablePublicAccessForSecurityGroup`(SG 의 0.0.0.0/0 22/3389 제거) 전용. 다른 룰에 붙이려면 `resource_type`·`target_id`·`parameter` 를 그 문서에 맞춘다 — `aws ssm describe-document --name <문서>` 로 파라미터 이름 확인. `AutomationAssumeRole` 이 없으면 복구가 조용히 실패한다.
- email 구독은 수신자가 확인 링크를 눌러야 `Confirmed` — `PendingConfirmation` 으로는 통지가 안 간다.
- GuardDuty 패턴의 `numeric` 비교(`[">=", 4]`)는 EventBridge 숫자 매칭 문법 — 문자열 `"4"` 로 쓰면 매칭 안 됨.

## 실전 구현 (참고용)

- set-02 task-2 module-3-event `terraform/eventbridge.tf`(룰 6종 + Lambda 타깃·permission), `terraform/config.tf`(recorder + INCOMING_SSH_DISABLED·REQUIRED_TAGS), `terraform/lambda/tag_alert/index.py`(SNS publish)
- set-08 task-2 module-3-event-handling `terraform/eventbridge.tf`(AuthorizeSecurityGroupIngress → Lambda), `terraform/sns.tf`
