# CloudTrail hardening KIT

CloudTrail의 **로그 무결성 검증**, 멀티 리전 추적, 선택적 CloudWatch Logs 연동과 SSE-KMS를 기존 Terraform 루트에 부착하는 COPY KIT이다. 이 디렉터리는 독립 state나 독립 `apply` 대상이 아니다.

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

## 포함 파일

| 파일 | 역할 |
| --- | --- |
| `cloudtrail.tf` | 로그 S3 버킷·버킷 정책, CloudTrail, 선택적 CloudWatch Logs·CMK 리소스 |
| `variables.tf` | Trail 이름, 멀티 리전, 로그·KMS 옵션 변수 |

## 부착 절차

대상 세트의 `task.md`, `mark.md`, `mark*.sh`, `NOTES.md`를 먼저 읽고 과제지가 요구한 Trail 이름·리전·로그 보존 기간을 확정한다. 대상 Terraform 루트에 두 파일을 **복사**한 뒤, 과제지 값만 `terraform.tfvars`에 넣는다.

```hcl
addon_trail_name            = "<과제지 Trail 이름>"
addon_trail_bucket_prefix   = "<전역 고유 로그 버킷 접두어>"
addon_trail_multi_region    = true  # 모든 리전 요구일 때만
addon_trail_cw_logs_enabled = true  # Logs/메트릭 필터 요구일 때만
addon_trail_log_group_name  = "/aws/cloudtrail/<trail>"
addon_trail_kms_enabled     = true  # SSE-KMS 요구일 때만
addon_trail_kms_alias       = "<alias/ 없이 입력>"
```

대상 루트에 이미 `aws_cloudtrail` 또는 Trail용 S3 버킷이 있으면 이 KIT를 그대로 복사해 중복 생성하지 않는다. 기존 리소스에는 `enable_log_file_validation = true`, 과제지에 맞는 `is_multi_region_trail`, `include_global_service_events`, CloudWatch Logs·KMS 참조만 이식한다. S3 버킷 notification은 리소스당 하나이므로 기존 notification 블록을 덮어쓰지 않는다.

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply
```

## VERIFY

```powershell
aws cloudtrail describe-trails --trail-name-list <Trail이름>
aws cloudtrail get-trail-status --name <Trail이름>
aws cloudtrail get-event-selectors --trail-name <Trail이름>
```

`IsLogging=true`, `LogFileValidationEnabled=true`와 과제지의 멀티 리전·글로벌 이벤트 값이 일치해야 한다. CloudWatch Logs를 켰다면 Trail의 `CloudWatchLogsLogGroupArn`과 `CloudWatchLogsRoleArn`도 확인한다. 이 검증은 기능 확인이며, 점수 판정은 해당 세트의 공식 채점 절차로 한다.

## 주의

기본 `event_selector`는 **management event**만 수집한다. S3 객체·Lambda 호출 같은 data event가 요구되면 기존 Trail의 event selector를 과제지 요구에 맞게 별도로 확장한다. KMS를 켜면 CloudTrail과 CloudWatch Logs 서비스 principal에 필요한 key policy가 함께 있어야 하며, 이 KIT의 정책 블록을 생략하면 적용이 실패할 수 있다.
