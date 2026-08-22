# 감사용 IAM Role 부착 KIT

ExternalId 조건 + 최대 세션 제한 + 인라인 최소권한 정책이 붙은 Role.

## 이 KIT이 맞나

- 과제지에 **"외부 감사자가 ExternalId로 Assume하는 읽기 전용 Role"·"감사 역할"** → 맞다.
- **Pod에 IAM 권한** → [irsa](../irsa/README.md) · **API 호출 감사 로그** → [cloudtrail-hardening](../cloudtrail-hardening/README.md).
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 현재 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| Audit Role | **없음** | **없음** | `aws_iam_role.audit` + `aws_iam_role_policy.audit` **있음** |
| ExternalId | — | — | `local.audit_external_id` (= `var.audit_external_id_prefix` + 선수번호) |
| `account_id` output | 있음 | 있음 | 있음 |

**set-07이 완성 원본이다** — `set-07/task-1/terraform/iam.tf` 의 Audit Role 절 + `variables.tf` 의 `audit_external_id_prefix` + `data.tf` 의 `local.audit_external_id` 을 복사한다.

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `iam-audit-role.tf` | `set-XX/task-1/terraform/` | trust(계정 root 또는 지정 principal + `sts:ExternalId`) · `aws_iam_role`(`max_session_duration`) · 인라인 정책 |
| `variables.tf` | `variables-audit-addon.tf` | `addon_audit_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_audit_role_name` | **필수** | **채점 스크립트가 `get-role` 로 직접 읽는다.** 과제지와 정확히 일치 |
| `addon_audit_external_id` | **필수** | `sts:ExternalId` 조건 값. 과제지가 선수 번호를 붙이라면 **그대로 조립** |
| `addon_audit_policy_name` | `"audit-policy"` | 인라인 정책 이름 |
| `addon_audit_trusted_principal_arns` | `[]` | 빈 목록이면 같은 계정 root |
| `addon_audit_max_session_duration` | `3600` | 초. **최소 3600**, 최대 43200 |
| `addon_audit_policy_statements` | 예시 | 인라인 정책 statement. **액션에 와일드카드를 쓰지 않는다** |

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_audit_role_name              = "skills-audit-role"
addon_audit_external_id            = "skills-audit-2026"   # 과제지가 "<prefix><선수번호>" 면 그대로 조립
addon_audit_policy_name            = "skills-audit-policy"
addon_audit_max_session_duration   = 3600
addon_audit_trusted_principal_arns = []                    # 빈 목록 = 같은 계정 root
addon_audit_policy_statements = [
  { sid = "DynamoRead", actions = ["dynamodb:GetItem", "dynamodb:Query"], resources = ["<테이블 ARN>", "<테이블 ARN>/index/*"] },
  { sid = "DescribeVpcAndCluster", actions = ["ec2:DescribeVpcs", "eks:DescribeCluster"], resources = ["*"] },
]
```

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## 1. Role 자체

```hcl
# 파일: set-XX/task-1/terraform/iam-audit-role.tf   (KIT에서 복사됨)
resource "aws_iam_role" "addon_audit" {
  name                 = var.addon_audit_role_name
  max_session_duration = var.addon_audit_max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.addon_audit_trust.json
}
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "audit_role_arn"    { value = aws_iam_role.addon_audit.arn }
output "audit_role_name"   { value = aws_iam_role.addon_audit.name }
output "audit_external_id" { value = var.addon_audit_external_id }
```

<details><summary><b>값 뽑기 — 세트별 (Assume 성공/실패 둘 다 확인한다)</b></summary>

| 세트 | Role 리소스 | output |
| --- | --- | --- |
| set-02 | 새로 만든다 | 위 블록 추가 |
| set-03 | 새로 만든다 | 위 블록 추가 |
| set-07 | `aws_iam_role.audit` **있음** | `output "audit_role_arn" { value = aws_iam_role.audit.arn }` · `output "audit_external_id" { value = local.audit_external_id }` |

```powershell
$arn = terraform output -raw audit_role_arn
$eid = terraform output -raw audit_external_id

# 1) ExternalId 를 주면 성공해야 한다
aws sts assume-role --role-arn $arn --role-session-name audit --external-id $eid --duration-seconds 3600 `
  --query "AssumedRoleUser.Arn"

# 2) ExternalId 없이는 AccessDenied 가 정상이다 (이게 채점 포인트다)
aws sts assume-role --role-arn $arn --role-session-name audit

aws iam get-role --role-name (terraform output -raw audit_role_name) `
  --query "Role.[MaxSessionDuration,AssumeRolePolicyDocument]"
```

set-07은 ExternalId가 **선수 번호를 포함**한다(`unicorn-audit-2026<선수번호>`). prefix만 넣고 번호를 빠뜨리면 채점이 실패한다:

```powershell
terraform console
> local.audit_external_id
```
</details>

## 2. 인라인 최소권한 정책

```hcl
# 파일: set-XX/task-1/terraform/iam-audit-role.tf
resource "aws_iam_role_policy" "addon_audit" {
  name   = var.addon_audit_policy_name
  role   = aws_iam_role.addon_audit.id
  policy = data.aws_iam_policy_document.addon_audit.json
}
```

<details><summary><b>값 뽑기 — 세트별 (리소스 ARN을 직접 참조로 조립한다)</b></summary>

tfvars에 ARN을 손으로 적지 말고 `.tf` 안에서 조립하는 쪽이 안전하다:

```hcl
# 파일: set-XX/task-1/terraform/iam-audit-role.tf
locals {
  addon_audit_statements = [
    { sid = "DynamoRead", actions = ["dynamodb:GetItem", "dynamodb:Query"],
      resources = [aws_dynamodb_table.data.arn, "${aws_dynamodb_table.data.arn}/index/*"] },   # ← 세트별 주소
    { sid = "S3Read", actions = ["s3:GetObject", "s3:ListBucket"],
      resources = [aws_s3_bucket.web.arn, "${aws_s3_bucket.web.arn}/*"] },
  ]
}
```

| 세트 | 테이블 주소 | 버킷 주소 | 테이블 CMK output |
| --- | --- | --- | --- |
| set-02 | `aws_dynamodb_table.data` | `aws_s3_bucket.web` | 없음 (`aws_kms_key.dynamodb`) |
| set-03 | `aws_dynamodb_table.book` | `aws_s3_bucket.static` | `db_kms_arn` |
| set-07 | `aws_dynamodb_table.concert` | `aws_s3_bucket.web` | `app_kms_arn` |

```powershell
aws iam get-role-policy --role-name (terraform output -raw audit_role_name) `
  --policy-name skills-audit-policy --query PolicyDocument

# Assume 한 자격증명으로 실제로 읽히는지
$c = aws sts assume-role --role-arn (terraform output -raw audit_role_arn) `
  --role-session-name audit --external-id (terraform output -raw audit_external_id) | ConvertFrom-Json
$env:AWS_ACCESS_KEY_ID     = $c.Credentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $c.Credentials.SecretAccessKey
$env:AWS_SESSION_TOKEN     = $c.Credentials.SessionToken
aws dynamodb describe-table --table-name (terraform output -raw table_name)
# 끝나면 반드시 지운다 — 채점 전 자격증명이 남아 있으면 안 된다
Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_SESSION_TOKEN
```

**CMK로 암호화된 테이블/버킷을 읽어야 하면** `kms:Decrypt` 문장을 추가한다:

```hcl
{ sid = "CmkDecrypt", actions = ["kms:Decrypt"], resources = [aws_kms_key.app.arn] },
```
</details>

## 3. 다른 계정이 Assume하는 경우

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_audit_trusted_principal_arns = ["arn:aws:iam::<감사계정ID>:root"]
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 계정이 하나뿐이라 기본값(같은 계정 root)이 맞다. 확인:

```powershell
terraform output -raw account_id        # 세 세트 모두 있음
aws iam get-role --role-name (terraform output -raw audit_role_name) `
  --query "Role.AssumeRolePolicyDocument.Statement[].Principal"
```

**trust에 계정 root를 두면 같은 계정의 모든 IAM principal이 Assume 가능하다**(ExternalId 조건은 걸려 있다). 과제지가 "특정 사용자/Role만"이면 그 ARN을 넣는다.
</details>

<details><summary><b>관리형 정책(ReadOnlyAccess 등) 부착 요구 시</b></summary>

```hcl
# 파일: set-XX/task-1/terraform/iam-audit-role.tf
resource "aws_iam_role_policy_attachment" "addon_audit_readonly" {
  role       = aws_iam_role.addon_audit.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

```powershell
aws iam list-attached-role-policies --role-name (terraform output -raw audit_role_name) `
  --query "AttachedPolicies[].[PolicyName,PolicyArn]" --output table
```

"최소 권한"을 채점하는 문항에 `ReadOnlyAccess` 를 붙이면 감점될 수 있다 — 과제지가 명시할 때만.
</details>

## VERIFY

```powershell
$arn = terraform output -raw audit_role_arn
$eid = terraform output -raw audit_external_id
aws sts assume-role --role-arn $arn --role-session-name audit --external-id $eid --query "AssumedRoleUser.Arn"
aws sts assume-role --role-arn $arn --role-session-name audit          # AccessDenied 가 정상
aws iam get-role --role-name (terraform output -raw audit_role_name) --query "Role.MaxSessionDuration"
```

## TROUBLESHOOT

- Role `name` 변경은 **재생성**, 정책·trust·세션 시간은 in-place다.
- **채점은 Role 이름·ExternalId를 정확히 읽는다** — `get-role` 의 `AssumeRolePolicyDocument` 에서 `sts:ExternalId` 값을 비교하거나 그 값으로 실제 `assume-role` 을 한다. **선수 번호를 빠뜨리지 않는다.**
- `max_session_duration` **최소 3600**. "1시간 이하" 요구면 3600 그대로 둔다(줄이는 건 호출자의 `--duration-seconds` 몫).
- "액션 와일드카드 금지"면 `dynamodb:*`·`ec2:Describe*` 를 쓰지 않는다. Describe/List 계열의 `Resource: "*"` 는 리소스 레벨 미지원이라 불가피하다 — 과제지가 리소스까지 제한하라면 그 액션을 빼거나 감독에게 확인한다.
- 지급 계정은 PowerUser 수준이지만 IAM Role 생성은 허용 전제다. AccessDenied면 코드가 아니라 Deny 정책이니 감독에게 확인한다.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/iam.tf` — `unicorn-audit-role` (Audit Role 절) · `variables.tf: audit_external_id_prefix` · `data.tf: local.audit_external_id` (**완성 복사 원본**)
