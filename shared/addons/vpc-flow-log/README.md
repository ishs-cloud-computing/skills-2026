# VPC Flow Log 부착 KIT

VPC Flow Log → CloudWatch Logs(또는 S3) 한 묶음.

## 이 KIT이 맞나

- 과제지에 **"VPC 트래픽 로그"·"Flow Log"** → 맞다.
- **애플리케이션 로그** → [observability](../observability/README.md) 경로 C · **API 호출 감사** → [cloudtrail-hardening](../cloudtrail-hardening/README.md).
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 현재 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| Flow Log | **없음** | **없음** | `aws_flow_log.this` **있음** |
| 로그 그룹 | — | — | `aws_cloudwatch_log_group.flowlog` |
| IAM Role | — | — | `aws_iam_role.flowlog` + `aws_iam_role_policy.flowlog` |
| 파일 | — | — | `flowlog.tf` |
| CMK | — | — | Platform CMK 암호화 |
| `vpc_id` output | 있음 | 있음 | 있음 |

**set-07은 이미 완성본이다** — 이 KIT 대신 `set-07/task-1/terraform/flowlog.tf` 를 복사하는 쪽이 빠르다.

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `flowlog.tf` | `set-XX/task-1/terraform/` | 로그 그룹(retention·선택 CMK) · IAM Role(trust `vpc-flow-logs.amazonaws.com`) · `aws_flow_log` |
| `variables.tf` | `variables-flowlog-addon.tf` | `addon_flowlog_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_flowlog_vpc_id` | **필수** | 직접 참조 권장 (`aws_vpc.this.id`) |
| `addon_flowlog_name` | `"vpc-flowlog"` | Flow Log·로그 그룹 Name 태그 |
| `addon_flowlog_log_group_name` | `"/vpc/flowlog"` | **과제지 명시 이름과 정확히 일치** |
| `addon_flowlog_role_name` | `"vpc-flowlog-role"` | 게시용 IAM Role 이름 |
| `addon_flowlog_traffic_type` | `"ALL"` | ALL / ACCEPT / REJECT |
| `addon_flowlog_retention_days` | `30` | 로그 그룹 보존 |
| `addon_flowlog_kms_key_arn` | `""` | CMK ARN. 빈 문자열이면 AWS 관리 키 |
| `addon_flowlog_aggregation_interval` | `600` | **60 또는 600만 허용** |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## FAST — terraform 없이 CLI 로 붙이기

Flow Log 는 기존 VPC 에 **붙이는** 리소스라 기존 것을 건드리지 않는다. S3 목적지는 IAM Role 도 필요 없다.

**대가**: terraform state 와 실물이 어긋난다. 이 세트에 이후 `apply` 를 걸면 되돌아가므로,
CLI 로 붙였으면 그 세트는 더 apply 하지 않거나 나중에 같은 값을 `.tf` 에도 넣는다.

```powershell
$VPC = aws ec2 describe-vpcs --filters Name=tag:Name,Values=<VPC 이름> `
  --query 'Vpcs[0].VpcId' --output text

# S3 목적지 — Role 이 필요 없어 제일 빠르다
aws ec2 create-flow-logs --resource-type VPC --resource-ids $VPC --traffic-type ALL `
  --log-destination-type s3 --log-destination arn:aws:s3:::<버킷>/<프리픽스>/ `
  --max-aggregation-interval 60 `
  --tag-specifications 'ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=<이름>}]'

# CloudWatch Logs 목적지 — 전달 Role 이 있어야 한다
aws logs create-log-group --log-group-name <로그그룹>
aws ec2 create-flow-logs --resource-type VPC --resource-ids $VPC --traffic-type ALL `
  --log-destination-type cloud-watch-logs --log-group-name <로그그룹> `
  --deliver-logs-permission-arn <flow-log Role ARN> --max-aggregation-interval 60
```

- 응답의 **`Unsuccessful` 배열을 반드시 본다.** 권한이나 목적지가 틀려도 명령 자체는 exit 0 이고 `FlowLogIds` 가 빈 채로 돌아온다.
- 첫 로그가 뜨기까지 **`--max-aggregation-interval 60` 이어도 몇 분** 걸린다. 채점 항목당 대기가 3분이면 먼저 만들어 두고 다른 것을 한다.
- CloudWatch 경로의 전달 Role 은 `vpc-flow-logs.amazonaws.com` 을 신뢰해야 한다. 이 Role 은 이름이 채점 대상일 수 있으니 아래 terraform 블록으로 만드는 편이 안전하다.

## 1. CloudWatch Logs 목적지

```hcl
# 파일: set-XX/task-1/terraform/flowlog.tf   (KIT에서 복사됨)
resource "aws_flow_log" "addon" {
  vpc_id                   = aws_vpc.this.id            # ← 직접 참조 권장
  traffic_type             = var.addon_flowlog_traffic_type
  iam_role_arn             = aws_iam_role.addon_flowlog.arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.addon_flowlog.arn
  max_aggregation_interval = var.addon_flowlog_aggregation_interval
  tags                     = { Name = var.addon_flowlog_name }
}
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "flowlog_id"        { value = aws_flow_log.addon.id }
output "flowlog_log_group" { value = aws_cloudwatch_log_group.addon_flowlog.name }
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 리소스 주소 | output |
| --- | --- | --- |
| set-02 | 새로 만든다 (`aws_flow_log.addon`) | 위 블록 추가 |
| set-03 | 새로 만든다 | 위 블록 추가 |
| set-07 | **`aws_flow_log.this` 가 이미 있다** | `output "flowlog_log_group" { value = aws_cloudwatch_log_group.flowlog.name }` |

```powershell
terraform output -raw vpc_id                # 세 세트 모두 있음
terraform output -raw flowlog_log_group

aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$(terraform output -raw vpc_id)" `
  --query "FlowLogs[].[FlowLogId,FlowLogStatus,TrafficType,LogDestinationType,LogGroupName]" --output table

# 스트림은 트래픽 발생 후 최대 10분(집계 600초) 뒤에 생긴다
aws logs describe-log-streams --log-group-name (terraform output -raw flowlog_log_group) --max-items 3
aws logs tail (terraform output -raw flowlog_log_group) --since 15m | Select-Object -First 5
```

채점이 촉박하면 `addon_flowlog_aggregation_interval = 60` 으로 낮춘다.
</details>

## 2. 로그 그룹 CMK 암호화

```hcl
# 파일: set-XX/task-1/terraform/flowlog.tf
# 기존 aws_cloudwatch_log_group 리소스 블록 *안에*
kms_key_id = var.addon_flowlog_kms_key_arn
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 쓸 키 | 키 ARN output |
| --- | --- | --- |
| set-02 | `aws_kms_key.s3` 재사용 또는 addon CMK | **없음** — [kms](../kms/README.md) 0번 |
| set-03 | `aws_kms_key.eks` / `.bucket` 등 | `eks_kms_arn` · `bucket_kms_arn` (있음) |
| set-07 | `aws_kms_key.platform` (이미 이 구성) | `platform_kms_arn` (있음) |

```powershell
terraform output -raw platform_kms_arn      # set-07
# → terraform.tfvars 의 addon_flowlog_kms_key_arn 에 넣는다

aws logs describe-log-groups --log-group-name-prefix (terraform output -raw flowlog_log_group) `
  --query "logGroups[].[logGroupName,kmsKeyId,retentionInDays]"
```

key policy에 `logs.<region>.amazonaws.com` 문장이 **필수**다 — 없으면 apply가 AccessDenied로 실패한다 ([kms](../kms/README.md) 3번).
</details>

## 3. S3 목적지 (과제지가 "S3에 저장"을 요구할 때)

```hcl
# 파일: set-XX/task-1/terraform/flowlog.tf
# KIT의 로그 그룹·IAM Role·Role 정책을 지우고 aws_flow_log 를 이걸로 바꾼다
resource "aws_flow_log" "addon" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.addon_flowlog_traffic_type
  log_destination_type     = "s3"
  log_destination          = "${aws_s3_bucket.web.arn}/flowlog/"   # ← 세트별 주소
  max_aggregation_interval = var.addon_flowlog_aggregation_interval

  destination_options {
    file_format                = "parquet"   # Athena 조회 요구면 parquet, 아니면 plain-text
    per_hour_partition         = true
    hive_compatible_partitions = false
  }

  tags = { Name = var.addon_flowlog_name }
}
```

S3 목적지는 IAM Role이 필요 없다.

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 쓸 버킷 | 주의 |
| --- | --- | --- |
| set-02 | `aws_s3_bucket.web` | 정적 호스팅 버킷과 섞인다 — **별도 버킷 권장** |
| set-03 | `aws_s3_bucket.static` | 동일 |
| set-07 | `aws_s3_bucket.web` | 동일 |

```powershell
terraform output -raw s3_bucket_name        # 세 세트 모두 있음
aws s3 ls "s3://$(terraform output -raw s3_bucket_name)/flowlog/" --recursive | Select-Object -First 5

aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$(terraform output -raw vpc_id)" `
  --query "FlowLogs[].[LogDestinationType,LogDestination,DestinationOptions]"
```

**기존 버킷 정책이 있으면** `delivery.logs.amazonaws.com` 의 `s3:PutObject`/`s3:GetBucketAcl` 문장을 직접 추가해야 한다 (자동 부착은 정책이 없을 때만). 세 세트 모두 OAC 정책이 이미 있으므로 **수동 추가가 필요하다.**
</details>

<details><summary><b>서브넷·ENI 단위 (VPC 대신)</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/flowlog.tf
# aws_flow_log 리소스 안에서 vpc_id 대신 하나만 지정한다
subnet_id = aws_subnet.this["priv-a"].id
# 또는
eni_id = "<eni-id>"
```

```powershell
terraform output -json private_subnet_ids    # 세 세트 모두 있음 (map)

aws ec2 describe-flow-logs --query "FlowLogs[].[ResourceId,FlowLogStatus]" --output table
```
</details>

## VERIFY

```powershell
aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$(terraform output -raw vpc_id)" `
  --query "FlowLogs[].[FlowLogId,FlowLogStatus,TrafficType,LogDestinationType,LogGroupName]" --output table
aws logs tail (terraform output -raw flowlog_log_group) --since 15m | Select-Object -First 5
```

## TROUBLESHOOT

- `traffic_type`·`log_destination`·`max_aggregation_interval` 변경은 Flow Log **재생성**(ForceNew)이지만 채점 영향은 없다.
- `vpc_id`/`subnet_id`/`eni_id` 는 **하나만** 지정한다.
- 로그 그룹 CMK를 쓰면 key policy에 logs 서비스 문장이 필수다.
- S3 목적지에 **기존 버킷 정책이 있으면 서비스 문장을 수동 추가**해야 한다.
- 채점은 보통 `describe-flow-logs` 로 `FlowLogStatus=ACTIVE`·`TrafficType`·`LogGroupName` 을 읽는다 — 이름·traffic type을 과제지 값과 정확히 맞춘다.
- 첫 로그 스트림은 트래픽 발생 후 최대 10분 뒤에 생긴다. 채점이 촉박하면 집계 간격을 60으로.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/flowlog.tf` — CW Logs 목적지 + Platform CMK 암호화 (**완성 복사 원본**)

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
