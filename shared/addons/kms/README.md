# KMS 부착 스니펫

`kms.tf`·`variables.tf` 를 `set-XX/task-1/terraform/` 으로 복사하고
`terraform.tfvars` 에 `addon_kms_alias` 를 넣는다.

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

## 함정

- **RDS·EBS·ECR·EKS 는 생성 후 암호화 변경 불가.** 기존 리소스 대상이면 재생성이 필요하므로,
  과제지가 기존 리소스 암호화를 요구하는지 신규 리소스 대상인지 먼저 판별한다.
  재생성은 기존 채점 항목을 깨뜨릴 수 있다 — 시간 대비 배점을 보고 결정한다.
- WAF(CLOUDFRONT) 로그 암호화까지 요구되면 us-east-1 키가 필요하다 — 단일 리전 키 대신
  MRK(`multi_region = true`) + `aws_kms_replica_key` 로 간다. set-07 task-1 `kms.tf` 참고.
- 회전 주기·alias 이름은 채점 스크립트가 직접 읽는 값이다. tfvars 로만 바꾼다.
