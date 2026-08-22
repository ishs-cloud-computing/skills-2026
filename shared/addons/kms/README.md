# KMS 부착 KIT

CMK(고객관리형 키)를 새로 만들고, 기존 리소스를 그 키로 암호화한다.

## 이 KIT이 맞나

- 과제지에 **"CMK"·"고객 관리형 키"·"저장 데이터 암호화"·"키 회전"** → 맞다.
- **기존** RDS·EBS·ECR·EKS를 암호화하라 → **생성 후 변경 불가**다. 재생성이 기존 채점 항목을 깨뜨리므로 배점부터 확인한다.
- EKS Secret 봉투 암호화만 요구 → [eks-logging-variants](../eks-logging-variants/README.md) 쪽이 더 가깝다.

## 복사할 파일

| 원본 | 대상 |
| --- | --- |
| `kms.tf` | `set-XX/task-1/terraform/kms-addon.tf` (세 세트 모두 `kms.tf` 가 이미 있다 — 이름을 바꿔 복사) |
| `variables.tf` | `set-XX/task-1/terraform/variables-kms-addon.tf` (기존 `variables.tf` 덮어쓰지 않는다) |

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 1개**는 채우지 않으면 apply되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_kms_alias` | **필수** | KMS alias 이름 (`alias/` 접두어 제외). 과제지 명시 이름과 정확히 일치 |
| `addon_kms_description` | `"task-1 addon CMK"` | 키 설명 |
| `addon_kms_rotation_days` | `365` | 자동 회전 주기(일). 과제지가 지정하면 그 값 (set-07은 90이었다) |

## CHECK · RUN

절차는 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴)과 같다.

```powershell
aws sts get-caller-identity   # 지급 계정인가
aws configure get region      # 과제지 리전인가
terraform fmt; terraform init; terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

## 0. 키 자체의 output — 다른 블록이 전부 이 값을 쓴다

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf  (없으면 새로 추가)
output "addon_kms_arn" {
  description = "addon CMK ARN — eksctl/k8s/tfvars 주입용"
  value       = aws_kms_key.addon.arn
}

output "addon_kms_alias" {
  value = aws_kms_alias.addon.name
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 `addon_kms_arn` 은 **새 output** 이다. 위 블록을 `outputs.tf` 에 추가한 뒤:

```powershell
terraform output -raw addon_kms_arn
terraform output -raw addon_kms_alias
```

기존 키 ARN은 세트마다 이미 output에 있다 — 새 키를 만들지 않고 재사용할 거면 아래를 쓴다.

| 세트 | 이미 있는 output |
| --- | --- |
| set-02 | `eks_kms_arn` (`aws_kms_key.eks`). `.s3` `.dynamodb` 는 output **없음** |
| set-03 | `eks_kms_arn` · `db_kms_arn` · `ecr_kms_arn` · `bucket_kms_arn` · `function_kms_arn` |
| set-07 | `platform_kms_arn` · `platform_kms_use1_arn`(us-east-1 replica) · `app_kms_arn` · `data_kms_arn` |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf  (없는 것 노출)
output "s3_kms_arn"       { value = aws_kms_key.s3.arn }
output "dynamodb_kms_arn" { value = aws_kms_key.dynamodb.arn }
```

```powershell
terraform output -raw platform_kms_arn     # set-07
terraform output -raw db_kms_arn           # set-03
```
</details>

## 1. S3 버킷 암호화 (기존 버킷에 추가 가능)

```hcl
# 파일: set-XX/task-1/terraform/s3.tf
# 세 세트 모두 aws_s3_bucket_server_side_encryption_configuration 이 이미 있다 —
# 새 리소스를 만들지 말고 그 블록의 kms_master_key_id 만 바꾼다.
resource "aws_s3_bucket_server_side_encryption_configuration" "addon" {
  bucket = aws_s3_bucket.web.id   # ← 세트별 주소로 치환

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.addon.arn
    }
    bucket_key_enabled = true
  }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 버킷 리소스 주소 | 기존 SSE 리소스 |
| --- | --- | --- |
| set-02 | `aws_s3_bucket.web` | `aws_s3_bucket_server_side_encryption_configuration.web` |
| set-03 | `aws_s3_bucket.static` | `...static` |
| set-07 | `aws_s3_bucket.web` | `...web` |

세 세트 모두 `s3_bucket_name` output이 **이미 있다**:

```powershell
terraform output -raw s3_bucket_name
aws s3api get-bucket-encryption --bucket (terraform output -raw s3_bucket_name)
```
</details>

CloudFront OAC가 이 버킷을 읽으면 key policy에 cloudfront 서비스 `Decrypt` 문장이 필요하다 — set-07 task-1 `kms.tf` 의 `kms_data` 정책을 복사한다.

## 2. DynamoDB 암호화 (기존 테이블에 추가 가능)

```hcl
# 파일: set-XX/task-1/terraform/dynamodb.tf
# 기존 aws_dynamodb_table 리소스 블록 *안에* 추가한다 (새 리소스 아님)
server_side_encryption {
  enabled     = true
  kms_key_arn = aws_kms_key.addon.arn
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 테이블 리소스 주소 | 현재 키 | 이름 output |
| --- | --- | --- | --- |
| set-02 | `aws_dynamodb_table.data` | `aws_kms_key.dynamodb` | **없음** — 아래 블록 추가 |
| set-03 | `aws_dynamodb_table.book` | `aws_kms_key.db` | `table_name` (이미 있음) |
| set-07 | `aws_dynamodb_table.concert` | `aws_kms_key.app` | **없음** — 아래 블록 추가 |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "table_name" { value = aws_dynamodb_table.data.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "table_name" { value = aws_dynamodb_table.concert.name }
```

```powershell
terraform output -raw table_name
aws dynamodb describe-table --table-name (terraform output -raw table_name) `
  --query "Table.SSEDescription"
```

세 세트 모두 **이미 CMK가 걸려 있다.** 키를 바꾸는 것도 in-place지만, 키를 지우면 테이블 접근이 불가해진다.
</details>

## 3. CloudWatch Logs 암호화 (기존 로그 그룹에 추가 가능)

```hcl
# 파일: set-XX/task-1/terraform/cloudwatch.tf
# 기존 aws_cloudwatch_log_group 리소스 블록 *안에* 추가한다
kms_key_id = aws_kms_key.addon.arn
```

key policy에 `logs.<region>.amazonaws.com` 문장이 **필수** — 없으면 apply가 AccessDenied로 실패한다. set-07 task-1 `kms.tf` 의 `AllowCloudWatchLogs` 문장을 `addon_kms_root` document에 추가한다.

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 앱 로그 그룹 | Lambda 로그 그룹 | 그 외 | output |
| --- | --- | --- | --- | --- |
| set-02 | `aws_cloudwatch_log_group.pod_logs` | `.book_lambda` | — | **없음** |
| set-03 | `.book_app` | `.book_function` | — | `app_log_group` (이미 있음) |
| set-07 | `.book_app` | `.get_booking` | `.eks_cluster` `.flowlog` `.waf`(us-east-1) | **없음** |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_log_group" { value = aws_cloudwatch_log_group.pod_logs.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_log_group" { value = aws_cloudwatch_log_group.book_app.name }
```

```powershell
aws logs describe-log-groups --log-group-name-prefix (terraform output -raw app_log_group) `
  --query "logGroups[].[logGroupName,kmsKeyId]"
```
</details>

## 4. ECR 암호화 (**생성 시에만**)

```hcl
# 파일: set-XX/task-1/terraform/ecr.tf
# 기존 aws_ecr_repository 리소스 블록 *안에* 추가 — 리포지토리 재생성이 발생한다
encryption_configuration {
  encryption_type = "KMS"
  kms_key         = aws_kms_key.addon.arn
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | ECR 리소스 주소 | 현재 키 |
| --- | --- | --- |
| set-02 | `aws_ecr_repository.book` | AWS 관리 `aws/ecr` (`kms_key` 생략) |
| set-03 | `aws_ecr_repository.book` | `aws_kms_key.ecr` |
| set-07 | `aws_ecr_repository.app` | `aws_kms_key.data` |

세 세트 모두 `ecr_repository_url` output이 이미 있다. **재생성되면 푸시한 이미지가 사라진다** — apply 후 다시 빌드·푸시하고 롤아웃한다:

```powershell
$url = terraform output -raw ecr_repository_url
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $url.Split('/')[0]
docker build -t "${url}:latest" .
docker push "${url}:latest"
kubectl rollout restart deployment/<앱> -n <ns>

aws ecr describe-repositories --repository-names $url.Split('/')[-1] `
  --query "repositories[].encryptionConfiguration"
```
</details>

## 5. EKS Secret 봉투 암호화 (**생성 시에만**)

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml
secretsEncryption:
  keyARN: "${ADDON_KMS_ARN}"
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 `eksctl/cluster.yaml` 은 `terraform output` 을 env로 읽어 렌더한다. 기존 키를 그대로 쓰면 아래 변수가 이미 있다.

| 세트 | 기존 env 변수 | 소스 output |
| --- | --- | --- |
| set-02 | `EKS_KMS_ARN` | `eks_kms_arn` |
| set-03 | `EKS_KMS_ARN` | `eks_kms_arn` |
| set-07 | `PLATFORM_KMS_ARN` | `platform_kms_arn` |

새 addon 키로 바꿀 때:

```powershell
$env:ADDON_KMS_ARN = terraform output -raw addon_kms_arn
```

**이미 만든 클러스터**에는 재생성 없이 부착 가능하다:

```powershell
eksctl utils enable-secrets-encryption --cluster wskorea26-cluster    --key-arn $env:ADDON_KMS_ARN --region ap-northeast-2
eksctl utils enable-secrets-encryption --cluster wsc2026-eks-cluster  --key-arn $env:ADDON_KMS_ARN --region ap-northeast-2
eksctl utils enable-secrets-encryption --cluster unicorn-eks-cluster  --key-arn $env:ADDON_KMS_ARN --region ap-northeast-2
```
</details>

## 6. 노드 EBS 암호화 (**생성 시에만**)

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml
# managedNodeGroups 항목 안에
volumeEncrypted: true
volumeKmsKeyID: "${ADDON_KMS_ARN}"
```

key policy에 AutoScaling 서비스 연결 역할 문장이 **필수** — 없으면 노드가 조용히 부팅 실패한다. set-07 task-1 `kms.tf` 의 `AllowAutoScalingUse`·`AllowAutoScalingGrant` 문장을 추가한다.

<details><summary><b>값 뽑기 — 세트별</b></summary>

```powershell
$env:ADDON_KMS_ARN = terraform output -raw addon_kms_arn
```

set-07은 storageclass(`k8s/01-storageclass.yaml`)도 CMK를 물고 있다 — 키를 바꾸면 거기도 같이 고친다. 노드 부팅 실패는 ASG 활동 로그에서만 보인다:

```powershell
kubectl get nodes
aws autoscaling describe-scaling-activities --auto-scaling-group-name <ASG명> --max-items 5 `
  --query "Activities[].[StatusCode,StatusMessage]"
```
</details>

## VERIFY

```powershell
aws kms describe-key --key-id (terraform output -raw addon_kms_alias) `
  --query "KeyMetadata.{Id:KeyId,Enabled:Enabled,Manager:KeyManager}"
aws kms get-key-rotation-status --key-id (terraform output -raw addon_kms_arn)
```

회전 주기·alias 이름은 채점 스크립트가 직접 읽는 값이다. 코드가 아니라 `terraform.tfvars` 로만 바꾼다.

## TROUBLESHOOT

- **RDS·EBS·ECR·EKS는 생성 후 암호화 변경 불가.** 기존 리소스 대상이면 재생성이 필요하다 — 기존 채점 항목이 깨질 수 있으니 시간 대비 배점을 보고 결정한다.
- **WAF(CLOUDFRONT) 로그 암호화**까지 요구되면 us-east-1 키가 필요하다. 단일 리전 키 대신 MRK(`multi_region = true`) + `aws_kms_replica_key` 로 간다 — set-07 task-1 `kms.tf` 가 그 형태다 (`platform` + `platform_use1`).
- **AccessDenied on apply** — 거의 항상 key policy에 서비스 principal 문장이 빠진 것이다. 계정 Deny 정책 문제가 아니다.
- 과제지에 CMK 이름이 없으면 **AWS 관리 키로 두는 게 맞다** (불필요 리소스 생성 감점 회피). set-02 `ecr.tf` 가 그 판단의 예다.
