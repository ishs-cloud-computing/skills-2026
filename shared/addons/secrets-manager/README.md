# secrets-manager 부착 스니펫

Secrets Manager 시크릿(JSON 키 맵, CMK 선택) + 읽기 IAM 정책·Role 연결 + 자동 회전(선택) 한 묶음.
set-07 task-1(과제지 4번 Secrets Manager), set-08 m1(DocDB 접속 정보), set-03 task-1(Grafana 계정) 후보에 대응.

## 파일

- `secrets.tf` — `aws_secretsmanager_secret`(kms_key_id) · `_version`(jsonencode 맵) · 읽기 정책 문서 + `aws_iam_policy` + Role 연결(for_each) · `aws_secretsmanager_secret_rotation` + `aws_lambda_permission`(회전 Lambda ARN 이 있을 때만)
- `variables.tf` — `addon_secret_*` 변수

## 부착 절차

1. `secrets.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 같은 루트 모듈이면 `var.addon_secret_reader_role_names` 를 `[aws_iam_role.<기존>.name]` 으로, `var.addon_secret_kms_key_arn` 을 `aws_kms_key.addon.arn` 으로 바꾼다.

   ```hcl
   addon_secret_name = "skills-nosql-docdb-secret"
   addon_secret_values = {
     username = "skillsadmin"
     password = "CHANGE-ME"              # 생성값을 쓰려면 아래 블록
     host     = "skills-docdb.cluster-xxxx.ap-northeast-2.docdb.amazonaws.com"
   }
   addon_secret_kms_key_arn          = ""    # CMK 요구 시 ARN
   addon_secret_recovery_window_days = 0
   addon_secret_read_policy_name     = "skills-secret-read"
   addon_secret_reader_role_names    = ["skills-app-role"]
   # 회전 요구 시에만
   addon_secret_rotation_lambda_arn = ""     # 예: arn:aws:lambda:ap-northeast-2:123456789012:function:SecretsManagerRotation
   addon_secret_rotation_days       = 30
   addon_secret_rotate_immediately  = false
   ```
3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws secretsmanager describe-secret --secret-id <이름> --query '[Name,KmsKeyId,RotationEnabled,RotationRules,RotationLambdaARN]'
   aws secretsmanager get-secret-value --secret-id <이름> --query SecretString --output text
   aws iam list-attached-role-policies --role-name <Role>
   ```

## 블록

값을 코드에 두지 않고 생성하려면(set-08 m1 패턴) tfvars 의 `password` 대신:

```hcl
# secrets.tf 옆 새 파일 또는 같은 파일에:
resource "random_password" "addon_secret" {
  length  = 24
  special = false # DocDB·RDS 금지 문자("/@) 회피
}

# aws_secretsmanager_secret_version.addon 의 secret_string 을:
secret_string = jsonencode(merge(var.addon_secret_values, { password = random_password.addon_secret.result }))
```

DB 엔진의 비밀번호도 같은 값으로 — `aws_docdb_cluster`/`aws_db_instance` 의 `master_password = random_password.addon_secret.result`.

기존 Role 인라인 정책에 읽기만 끼워 넣으려면 `aws_iam_policy`·attachment 대신:

```hcl
# 기존 aws_iam_policy_document 안에:
statement {
  actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
  resources = [aws_secretsmanager_secret.addon.arn]
}
```

## 함정

- 전부 신규 리소스 — 기존 리소스 재생성 없음. 시크릿 `name` 변경은 ⚠ 재생성. `secret_string` 변경은 새 버전(AWSCURRENT 이동)이며 in-place.
- **이름 재사용**: `recovery_window_in_days` 7~30 으로 지운 시크릿은 그 기간 동안 같은 이름으로 못 만든다(`InvalidRequestException: scheduled for deletion`). 기본 0. 콘솔로 지운 것이 걸려 있으면 `aws secretsmanager delete-secret --secret-id <이름> --force-delete-without-recovery`.
- 지급 앱이 시크릿 이름·JSON 키 이름을 상수로 읽는다(set-08 m1: `username/password/host`, host 는 scheme·port 없는 hostname). 키 이름 오타는 앱 기능 검증 전체 실패.
- `secret_string` 은 state 에 평문으로 남는다 — tfstate 미커밋 규칙 유지. `sensitive = true` 라 plan 출력에는 가려진다.
- CMK 를 쓰면 읽는 Role 에 `kms:Decrypt` 가 필요(스니펫이 자동 추가). 다른 계정/서비스 principal 이 읽으면 key policy 도 필요.
- 회전: `rotation_lambda_arn` 은 **이미 존재하는** 함수여야 한다. 스니펫은 함수 ARN 만 받고 함수는 만들지 않는다. 확인 필요 — 회전 Lambda 는 보통 SAR 템플릿(`SecretsManagerRotationTemplate`, `SecretsManagerMongoDBRotationSingleUser` 등)을 배포해 만드는데 Terraform 으로는 `aws_serverlessapplicationrepository_cloudformation_stack` 이 필요하고 함수가 DB 와 같은 VPC 에 있어야 한다. 과제지가 회전 Lambda 를 직접 주지 않으면 배점 대비 시간을 본다.
- `rotate_immediately` 기본을 false 로 두었다 — true 면 apply 시 회전이 1회 돌고 Lambda 가 실패하면 apply 도 실패한다. 채점이 `RotationEnabled=true` + 주기만 보면 false 로 충분. "마지막 회전 시각" 까지 보면 true 로 하거나 `aws secretsmanager rotate-secret --secret-id <이름>` 을 수동 실행.
- `aws_lambda_permission` 이 없으면 회전 설정이 `AccessDeniedException: Secrets Manager cannot invoke the specified Lambda function` 으로 거부된다 — 스니펫이 `depends_on` 으로 순서 강제.

## 실전 구현 (참고용)

- set-08 task-2 module-1-nosql `terraform/secrets.tf`(random_password + JSON 시크릿, recovery 0)
- 읽기 정책·회전 실전 구현 없음
