# KMS 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

`kms.tf`·`variables.tf` 를 `set-XX/task-1/terraform/` 으로 복사하고
`terraform.tfvars` 에 `addon_kms_alias` 를 넣는다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 1개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_kms_alias` | **필수** | KMS alias 이름 (alias/ 접두어 제외). 과제지 명시 이름과 정확히 일치시킨다 |
| `addon_kms_description` | `"task-1 addon CMK"` | 키 설명 (콘솔·채점 스크립트 표시용) |
| `addon_kms_rotation_days` | `365` | 자동 회전 주기 (일). 과제지가 지정하면 그 값으로 (set-07 은 90 이었다) |

## KEEP — 건드리지 않는다

- 기존 세트의 리소스·이름·CIDR. 이름이 충돌하면 기존 것을 지우지 말고 **이 KIT 쪽 변수를 리네임**한다.
- 공식 지급물 — `provided/`, `task.md`, `mark.md`, `mark*.sh`.
- `plan` 에 기존 리소스의 replace/delete 가 보이면 apply 하지 말고 멈춘다.

## CHECK — apply 전 계정·리전

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
```

## RUN

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 Kit의 state를 건드리지 않는다.

```powershell
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

복사할 파일과 순서는 아래 본문을 따른다.

## VERIFY / SCORE

- **VERIFY** = 이 README 본문의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 아래 함정은 이 KIT 고유 문제다.

## 부착 패턴 — 기존 리소스에 CMK 연결

과제지가 "X 를 CMK 로 암호화" 를 요구하면 아래 블록을 해당 리소스 파일에 추가한다.

### S3 (기존 버킷에 추가 가능)

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "addon" {
  bucket = aws_s3_bucket.<기존>.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.addon.arn
    }
    bucket_key_enabled = true
  }
}
```

CloudFront OAC 가 이 버킷을 읽으면 key policy 에 cloudfront 서비스 Decrypt 문장이 필요하다
— set-07 task-1 `kms.tf` 의 `kms_data` 정책을 복사한다.

### DynamoDB (기존 테이블에 추가 가능)

```hcl
# aws_dynamodb_table 리소스 안에:
server_side_encryption {
  enabled     = true
  kms_key_arn = aws_kms_key.addon.arn
}
```

### CloudWatch Logs (기존 로그 그룹에 추가 가능)

```hcl
# aws_cloudwatch_log_group 리소스 안에:
kms_key_id = aws_kms_key.addon.arn
```

key policy 에 logs 서비스 문장이 **필수** — 없으면 apply 가 AccessDenied 로 실패한다.
set-07 task-1 `kms.tf` 의 `AllowCloudWatchLogs` 문장을 `addon_kms_root` document 에 추가한다.

### ECR (생성 시에만)

```hcl
# aws_ecr_repository 리소스 안에:
encryption_configuration {
  encryption_type = "KMS"
  kms_key         = aws_kms_key.addon.arn
}
```

### EKS Secret Envelope (생성 시에만)

```yaml
# eksctl cluster.yaml:
secretsEncryption:
  keyARN: "${ADDON_KMS_ARN}"
```

기존 클러스터에는 `eksctl utils enable-secrets-encryption --cluster <이름> --key-arn <ARN>` 로 부착 가능.

### 노드 EBS (생성 시에만)

```yaml
# managedNodeGroups 항목 안에:
volumeEncrypted: true
volumeKmsKeyID: "${ADDON_KMS_ARN}"
```

key policy 에 AutoScaling 서비스 연결 역할 문장이 **필수** (없으면 노드가 조용히 부팅 실패한다)
— set-07 task-1 `kms.tf` 의 `AllowAutoScalingUse`·`AllowAutoScalingGrant` 문장을 추가한다.

## TROUBLESHOOT — 이 KIT 고유 함정
- **RDS·EBS·ECR·EKS 는 생성 후 암호화 변경 불가.** 기존 리소스 대상이면 재생성이 필요하므로,
  과제지가 기존 리소스 암호화를 요구하는지 신규 리소스 대상인지 먼저 판별한다.
  재생성은 기존 채점 항목을 깨뜨릴 수 있다 — 시간 대비 배점을 보고 결정한다.
- WAF(CLOUDFRONT) 로그 암호화까지 요구되면 us-east-1 키가 필요하다 — 단일 리전 키 대신
  MRK(`multi_region = true`) + `aws_kms_replica_key` 로 간다. set-07 task-1 `kms.tf` 참고.
- 회전 주기·alias 이름은 채점 스크립트가 직접 읽는 값이다. tfvars 로만 바꾼다.
