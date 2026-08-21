# vpc-flow-log 부착 스니펫

VPC Flow Log → CloudWatch Logs(또는 S3) 한 묶음. 1과제 Security/Observability 옵션
("VPC 트래픽 로그 수집", set-02/03/05/08/09 task-1 후보)과 set-02 task-2 m2/m4 의
네트워크 로그 문항에 대응한다.

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

- `flowlog.tf` — 로그 그룹(retention·선택 CMK) · IAM Role(trust `vpc-flow-logs.amazonaws.com`) · `aws_flow_log`(VPC, CW Logs 목적지)
- `variables.tf` — `addon_flowlog_*` 변수. 로그 그룹·Role 이름은 과제지 명시값으로 tfvars 에서 덮어쓴다

## 부착 절차

1. `flowlog.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 기존 VPC 를 직접 참조하려면 `var.addon_flowlog_vpc_id` 를 `aws_vpc.<기존>.id` 로 바꾼다.

   ```hcl
   addon_flowlog_vpc_id         = "vpc-0123456789abcdef0"
   addon_flowlog_name           = "skills-vpc-flowlog"
   addon_flowlog_log_group_name = "/skills/vpc/flowlog"
   addon_flowlog_role_name      = "skills-vpc-flowlog-role"
   addon_flowlog_traffic_type   = "ALL"          # ALL / ACCEPT / REJECT
   addon_flowlog_retention_days = 30
   addon_flowlog_kms_key_arn    = ""             # CMK 요구 시 ARN
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws ec2 describe-flow-logs --filter Name=resource-id,Values=<VPC ID> --query 'FlowLogs[].[FlowLogId,FlowLogStatus,TrafficType,LogDestinationType,LogGroupName]' --output table
   aws logs describe-log-streams --log-group-name /skills/vpc/flowlog --max-items 3   # 스트림은 트래픽 발생 후 ~10분
   ```

## 블록

### S3 목적지 (과제지가 "S3 에 저장" 을 요구할 때)

`flowlog.tf` 의 로그 그룹·IAM Role·Role 정책을 지우고 `aws_flow_log` 를 아래로 바꾼다.
S3 목적지는 IAM Role 이 필요 없다 — 버킷 정책은 서비스가 자동으로 붙인다(기존 정책이 있으면 수동 추가 필요).

```hcl
resource "aws_flow_log" "addon" {
  vpc_id                   = var.addon_flowlog_vpc_id
  traffic_type             = var.addon_flowlog_traffic_type
  log_destination_type     = "s3"
  log_destination          = "arn:aws:s3:::<버킷이름>/flowlog/"   # 또는 "${aws_s3_bucket.<기존>.arn}/flowlog/"
  max_aggregation_interval = var.addon_flowlog_aggregation_interval

  destination_options {
    file_format                = "parquet"   # 과제지가 Athena 조회를 요구하면 parquet, 아니면 plain-text
    per_hour_partition         = true
    hive_compatible_partitions = false
  }

  tags = { Name = var.addon_flowlog_name }
}
```

### 서브넷·ENI 단위 (VPC 대신)

```hcl
# aws_flow_log 리소스 안에서 vpc_id 대신:
subnet_id = "<subnet-id>"     # 또는 eni_id = "<eni-id>"
```

## 함정

- 전부 신규 리소스 — 기존 리소스 재생성 없음. `traffic_type`·`log_destination`·`max_aggregation_interval` 변경은 ⚠ Flow Log 재생성(ForceNew)이나 채점 영향 없음.
- `vpc_id`/`subnet_id`/`eni_id` 는 **하나만** 지정한다.
- 로그 그룹 CMK 암호화 요구 시 key policy 에 `logs.<region>.amazonaws.com` 문장이 **필수** — 없으면 apply 가 AccessDenied. kms/README 의 CloudWatch Logs 절 참고.
- S3 목적지에 기존 버킷 정책이 있으면 `delivery.logs.amazonaws.com` 의 `s3:PutObject`/`s3:GetBucketAcl` 문장을 직접 추가해야 한다(자동 부착은 정책이 없을 때만).
- 채점 스크립트는 보통 `describe-flow-logs` 로 `FlowLogStatus=ACTIVE`·`TrafficType`·`LogGroupName` 을 읽는다 — 로그 그룹 이름·traffic type 은 과제지 값과 정확히 맞춘다.
- 첫 로그 스트림은 트래픽 발생 후 최대 10분(집계 600초) 뒤에 생긴다. 채점 시간이 촉박하면 `addon_flowlog_aggregation_interval = 60`.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/flowlog.tf` — CW Logs 목적지 + Platform CMK 암호화
