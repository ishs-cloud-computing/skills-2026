# Secrets Manager 부착 KIT

시크릿(JSON 키 맵, CMK 선택) + 읽기 IAM 정책·Role 연결 + 자동 회전(선택).

## 이 KIT이 맞나

- 과제지에 **"Secrets Manager"·"시크릿 회전"·"자격증명을 코드에 두지 않는다"** → 맞다.
- **환경변수 암호화**만 요구 → [lambda-hardening](../lambda-hardening/README.md) 3번(`kms_key_arn`·`aws_kms_ciphertext`)이 더 가깝다.
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 현재 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| Secrets Manager | **없음** | **없음** | **없음** |
| 지금 비밀값을 어디 두나 | `var.grafana_admin_password` (tfvars) | `var.grafana_admin_password` | 앱 환경변수 |
| 읽을 Role 후보 | `aws_iam_role.book_lambda` (IRSA는 policy) | `aws_iam_role.book_pod` · `.book_function` · `.grafana` | `aws_iam_role.book_app` · `.get_booking` |
| 쓸 수 있는 CMK | `aws_kms_key.s3` | `aws_kms_key.function` · `.bucket` | `aws_kms_key.app` · `.platform` |

**세 세트 모두 Secrets Manager가 없다.** 가장 가까운 실전 원본은 set-08 task-2 module-1-nosql `terraform/secrets.tf` 다.

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `secrets.tf` | `set-XX/task-1/terraform/` | `aws_secretsmanager_secret`(kms_key_id) · `_version`(jsonencode) · 읽기 정책 + Role 연결(for_each) · 회전(선택) |
| `variables.tf` | `variables-secret-addon.tf` | `addon_secret_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_secret_name` | **필수** | **지급 앱이 상수로 읽는 이름**과 정확히 일치 |
| `addon_secret_values` | **필수** | JSON 키/값 맵. **키 이름 오타는 앱 기능 검증 전체 실패** |
| `addon_secret_kms_key_arn` | `""` | 빈 문자열이면 AWS 관리 키 `aws/secretsmanager` |
| `addon_secret_recovery_window_days` | `0` | 0 = 즉시 삭제(재생성 가능), 7~30 = 유예 |
| `addon_secret_read_policy_name` | `"skills-secret-read"` | 읽기 정책 이름 |
| `addon_secret_reader_role_names` | `[]` | 정책을 붙일 기존 Role 이름 목록 |
| `addon_secret_rotation_lambda_arn` | `""` | **이미 존재하는** 함수 ARN. 빈 문자열이면 회전 리소스를 안 만든다 |
| `addon_secret_rotation_days` | `30` | 회전 주기 |
| `addon_secret_rotate_immediately` | `false` | true면 apply 시 1회 회전 — Lambda가 실패하면 apply도 실패 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## 1. 시크릿 본체

```hcl
# 파일: set-XX/task-1/terraform/secrets.tf   (KIT에서 복사됨)
resource "aws_secretsmanager_secret" "addon" {
  name                    = var.addon_secret_name
  kms_key_id              = var.addon_secret_kms_key_arn != "" ? var.addon_secret_kms_key_arn : null
  recovery_window_in_days = var.addon_secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "addon" {
  secret_id     = aws_secretsmanager_secret.addon.id
  secret_string = jsonencode(var.addon_secret_values)
}
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "secret_arn"  { value = aws_secretsmanager_secret.addon.arn }
output "secret_name" { value = aws_secretsmanager_secret.addon.name }
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```powershell
terraform output -raw secret_name
terraform output -raw secret_arn

aws secretsmanager describe-secret --secret-id (terraform output -raw secret_name) `
  --query "[Name,KmsKeyId,RotationEnabled,RotationRules,RotationLambdaARN]"
aws secretsmanager get-secret-value --secret-id (terraform output -raw secret_name) `
  --query SecretString --output text
```

CMK를 쓸 때 세트별 키:

| 세트 | 후보 키 | 키 ARN output |
| --- | --- | --- |
| set-02 | `aws_kms_key.s3` | **없음** — [kms](../kms/README.md) 0번에서 노출 |
| set-03 | `aws_kms_key.function` | `function_kms_arn` (있음) |
| set-07 | `aws_kms_key.app` | `app_kms_arn` (있음) |

```powershell
terraform output -raw function_kms_arn     # set-03
terraform output -raw app_kms_arn          # set-07
# → terraform.tfvars 의 addon_secret_kms_key_arn 에 넣거나 .tf 에서 직접 참조
```

**`secret_string` 은 state에 평문으로 남는다** — tfstate 미커밋 규칙을 지킨다. `sensitive = true` 라 plan 출력에는 가려진다.
</details>

## 2. 값을 코드에 두지 않고 생성

```hcl
# 파일: set-XX/task-1/terraform/secrets.tf
resource "random_password" "addon_secret" {
  length  = 24
  special = false     # DB 엔진 금지 문자("/@) 회피
}
```

```hcl
# 파일: set-XX/task-1/terraform/secrets.tf
# aws_secretsmanager_secret_version.addon 의 secret_string 을 교체
secret_string = jsonencode(merge(var.addon_secret_values, { password = random_password.addon_secret.result }))
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "secret_password" {
  value     = random_password.addon_secret.result
  sensitive = true
}
```

```powershell
terraform output -raw secret_password
# 시크릿에 실제로 들어간 값과 대조
aws secretsmanager get-secret-value --secret-id (terraform output -raw secret_name) `
  --query SecretString --output text | ConvertFrom-Json
```

Grafana 비밀번호를 시크릿으로 옮기는 경우 세트별 소비 지점:

| 세트 | 지금 값이 들어가는 곳 |
| --- | --- |
| set-02 | `output grafana_admin_password` → `k8s/monitoring/kube-prometheus-stack-values.yaml` |
| set-03 | `var.grafana_admin_password` → 같은 values |
| set-07 | 같은 values |

시크릿으로 바꾸면 values 렌더 시점에 `get-secret-value` 로 읽어 넣는다:

```powershell
$pw = (aws secretsmanager get-secret-value --secret-id (terraform output -raw secret_name) `
  --query SecretString --output text | ConvertFrom-Json).password
```
</details>

## 3. 읽기 정책 + Role 연결

```hcl
# 파일: set-XX/task-1/terraform/secrets.tf   (KIT에서 복사됨)
resource "aws_iam_policy" "addon_secret_read" {
  name   = var.addon_secret_read_policy_name
  policy = data.aws_iam_policy_document.addon_secret_read.json
}

resource "aws_iam_role_policy_attachment" "addon_secret_read" {
  for_each   = toset(var.addon_secret_reader_role_names)
  role       = each.key
  policy_arn = aws_iam_policy.addon_secret_read.arn
}
```

기존 Role의 인라인 정책에 끼워 넣으려면:

```hcl
# 파일: set-XX/task-1/terraform/iam.tf
# 기존 aws_iam_policy_document 안에
statement {
  actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
  resources = [aws_secretsmanager_secret.addon.arn]
}
```

<details><summary><b>값 뽑기 — 세트별 (Role 이름)</b></summary>

| 세트 | 읽을 Role 후보 | Role 이름 output |
| --- | --- | --- |
| set-02 | `aws_iam_role.book_lambda` (앱은 IRSA policy라 Role이 eksctl 생성) | **없음** |
| set-03 | `aws_iam_role.book_pod` · `.book_function` · `.grafana` | `pod_identity_role_arns` (map, ARN만) |
| set-07 | `aws_iam_role.book_app` · `.get_booking` | `pod_identity_role_arns` (map, ARN만) |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "reader_role_names" {
  value = {
    lambda = aws_iam_role.book_lambda.name        # 세트별 주소
    pod    = aws_iam_role.book_pod.name
  }
}
```

```powershell
terraform output -json reader_role_names
# → terraform.tfvars 의 addon_secret_reader_role_names 에 넣는다

aws iam list-attached-role-policies --role-name <Role> `
  --query "AttachedPolicies[].[PolicyName,PolicyArn]" --output table

# Pod 안에서 실제로 읽히는지 (최종 확인)
kubectl exec deploy/<앱> -n <ns> -- aws secretsmanager get-secret-value `
  --secret-id (terraform output -raw secret_name) --query SecretString --output text
```

**CMK를 쓰면 읽는 Role에 `kms:Decrypt` 가 필요하다** (KIT이 자동 추가). set-02는 IRSA라 Role이 eksctl 생성이므로 policy ARN을 `iam.serviceAccounts.attachPolicyARNs` 에 추가하는 쪽이 맞다 → [irsa](../irsa/README.md) 1번.
</details>

## 4. 자동 회전 (선택)

```hcl
# 파일: set-XX/task-1/terraform/secrets.tf   (KIT에서 복사됨)
resource "aws_secretsmanager_secret_rotation" "addon" {
  count               = var.addon_secret_rotation_lambda_arn == "" ? 0 : 1
  secret_id           = aws_secretsmanager_secret.addon.id
  rotation_lambda_arn = var.addon_secret_rotation_lambda_arn
  rotate_immediately  = var.addon_secret_rotate_immediately

  rotation_rules {
    automatically_after_days = var.addon_secret_rotation_days
  }

  depends_on = [aws_lambda_permission.addon_secret_rotation]
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**KIT은 함수 ARN만 받고 회전 Lambda를 만들지 않는다.** 세 세트 모두 회전 Lambda가 없다.

```powershell
# 계정에 이미 있는 회전 함수 찾기
aws lambda list-functions --query "Functions[?contains(FunctionName,'Rotation')].[FunctionName,FunctionArn]" --output table

terraform output -raw secret_name
aws secretsmanager describe-secret --secret-id (terraform output -raw secret_name) `
  --query "[RotationEnabled,RotationRules.AutomaticallyAfterDays,RotationLambdaARN,LastRotatedDate]"

# 수동 1회 회전 (채점이 "마지막 회전 시각"을 볼 때)
aws secretsmanager rotate-secret --secret-id (terraform output -raw secret_name)
```

회전 Lambda는 보통 SAR 템플릿(`SecretsManagerRotationTemplate` 등)을 배포해 만든다. Terraform으로는 `aws_serverlessapplicationrepository_cloudformation_stack` 이 필요하고 함수가 DB와 같은 VPC에 있어야 한다 — **과제지가 회전 Lambda를 직접 주지 않으면 배점 대비 시간을 먼저 본다.**

`aws_lambda_permission` 이 없으면 회전 설정이 `AccessDeniedException: Secrets Manager cannot invoke the specified Lambda function` 으로 거부된다.
</details>

## VERIFY

```powershell
$s = terraform output -raw secret_name
aws secretsmanager describe-secret --secret-id $s `
  --query "[Name,KmsKeyId,RotationEnabled,RotationRules,RotationLambdaARN]"
aws secretsmanager get-secret-value --secret-id $s --query SecretString --output text
```

## TROUBLESHOOT

- 시크릿 `name` 변경은 **재생성**. `secret_string` 변경은 새 버전(AWSCURRENT 이동)이며 in-place다.
- **이름 재사용 함정**: `recovery_window_in_days` 7~30으로 지운 시크릿은 그 기간 동안 같은 이름으로 못 만든다(`InvalidRequestException: scheduled for deletion`). 걸렸으면:
  ```powershell
  aws secretsmanager delete-secret --secret-id <이름> --force-delete-without-recovery
  ```
- 지급 앱이 **시크릿 이름·JSON 키 이름을 상수로 읽는다.** 키 이름 오타는 앱 기능 검증 전체 실패다.
- `secret_string` 은 state에 평문으로 남는다.
- CMK를 쓰면 읽는 Role에 `kms:Decrypt` 가 필요하다.
- 회전 Lambda는 **이미 존재하는** 함수여야 한다.
- `rotate_immediately = true` 면 Lambda 실패 시 apply도 실패한다. 채점이 `RotationEnabled=true` + 주기만 보면 false로 충분하다.

## 실전 구현 (참고용)

- set-08 task-2 module-1-nosql `terraform/secrets.tf` — `random_password` + JSON 시크릿, recovery 0 (**가장 가까운 원본**)
- 읽기 정책·회전은 실전 구현이 없다.

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
