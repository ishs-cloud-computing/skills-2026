# iam-audit-role 부착 스니펫

ExternalId 조건 + 최대 세션 제한 + 인라인 최소권한 정책이 붙은 감사용 IAM Role.
1과제 Security 옵션("외부 감사자가 ExternalId 로 Assume 하는 읽기 전용 Role", set-02/03/05 task-1 후보)에 대응한다.

## 파일

- `iam-audit-role.tf` — trust(계정 root 또는 지정 principal + `sts:ExternalId`) · `aws_iam_role`(`max_session_duration`) · 인라인 정책(statement 목록 변수)
- `variables.tf` — `addon_audit_*` 변수. Role 이름·ExternalId 는 필수, 정책 statement 는 tfvars 로 교체

## 부착 절차

1. `iam-audit-role.tf`·`variables.tf` 를 `set-XX/task-1/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 기존 리소스 ARN 을 직접 참조하려면 tfvars 대신 `variables.tf` 의 default 를 지우고 `.tf` 안에서 `aws_dynamodb_table.<기존>.arn` 으로 statements 를 로컬로 조립한다.

   ```hcl
   addon_audit_role_name            = "skills-audit-role"
   addon_audit_external_id          = "skills-audit-2026"       # 과제지가 "<prefix><선수번호>" 면 그대로 조립
   addon_audit_policy_name          = "skills-audit-policy"
   addon_audit_max_session_duration = 3600
   addon_audit_trusted_principal_arns = []                       # 빈 목록 = 같은 계정 root
   addon_audit_policy_statements = [
     { sid = "DynamoRead", actions = ["dynamodb:GetItem", "dynamodb:Query"], resources = ["arn:aws:dynamodb:ap-northeast-2:123456789012:table/skills-table", "arn:aws:dynamodb:ap-northeast-2:123456789012:table/skills-table/index/*"] },
     { sid = "DescribeVpcAndCluster", actions = ["ec2:DescribeVpcs", "eks:DescribeCluster"], resources = ["*"] },
   ]
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증 (Assume 성공 + ExternalId 없이 실패 둘 다 확인):

   ```powershell
   aws sts assume-role --role-arn arn:aws:iam::<ACCOUNT>:role/skills-audit-role --role-session-name audit --external-id skills-audit-2026 --duration-seconds 3600
   aws sts assume-role --role-arn arn:aws:iam::<ACCOUNT>:role/skills-audit-role --role-session-name audit   # AccessDenied 가 정상
   aws iam get-role --role-name skills-audit-role --query 'Role.[MaxSessionDuration,AssumeRolePolicyDocument]'
   ```

## 블록

### 다른 계정(감사 계정) 이 Assume 하는 경우

```hcl
addon_audit_trusted_principal_arns = ["arn:aws:iam::<감사계정ID>:root"]
```

### CMK 로 암호화된 테이블/버킷을 읽어야 할 때

```hcl
# addon_audit_policy_statements 에 추가:
{ sid = "CmkDecrypt", actions = ["kms:Decrypt"], resources = ["<CMK ARN>"] },
```

### 관리형 정책(ReadOnlyAccess 등) 붙이기 요구 시

```hcl
resource "aws_iam_role_policy_attachment" "addon_audit_readonly" {
  role       = aws_iam_role.addon_audit.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

## 함정

- 전부 신규 리소스 — 기존 리소스 재생성 없음. Role `name` 변경은 ⚠ 재생성, 정책·trust·세션 시간은 in-place.
- **채점 스크립트는 Role 이름·ExternalId 를 정확히 읽는다**(`get-role` → `AssumeRolePolicyDocument` 의 `sts:ExternalId` 값 비교, 또는 그 ExternalId 로 실제 `assume-role`). set-07 은 `unicorn-audit-2026<선수번호>` 처럼 선수 번호를 붙였다 — prefix 만 넣고 번호를 빠뜨리지 않는다.
- `max_session_duration` 최소 3600. "1시간 이하" 요구면 3600 그대로(Assume 시 `--duration-seconds` 로 줄이는 건 호출자 몫).
- "액션 와일드카드 금지" 면 `actions` 에 `dynamodb:*`·`ec2:Describe*` 를 쓰지 않는다. 채점이 정책 JSON 에서 `*` 를 찾는다. Describe/List 계열의 `Resource: "*"` 는 리소스 레벨 미지원이라 불가피 — 과제지가 리소스까지 제한하라면 해당 액션을 빼거나 감독에게 확인.
- trust 에 계정 root 를 두면 같은 계정의 **모든** IAM principal 이 Assume 가능하다(ExternalId 조건은 있음). 과제지가 "특정 사용자/Role 만" 이면 `addon_audit_trusted_principal_arns` 에 그 ARN 을 넣는다.
- 지급 계정은 PowerUser 수준이지만 IAM Role 생성은 허용 전제(CLAUDE.md). AccessDenied 가 나면 코드가 아니라 Deny 정책 — 감독에게 확인.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/iam.tf` — `unicorn-audit-role` (Audit Role 절), `variables.tf: audit_external_id_prefix`, `data.tf: local.audit_external_id`
