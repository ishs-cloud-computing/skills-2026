# WAF 부착 KIT — Web ACL 신규 생성

Web ACL을 새로 만들고 ALB / API Gateway / CloudFront 앞단에 건다.

## 이 KIT이 맞나

- 과제지에 **"WAF를 생성"·"Web ACL을 구성"** → 맞다.
- **이미 Web ACL이 있고 룰만 추가**하라 → [waf-extra-rules](../waf-extra-rules/README.md).
- set-03(`aws_wafv2_web_acl.wsc2026`)·set-07(`aws_wafv2_web_acl.unicorn`)은 **이미 Web ACL이 있다.** 이 세트가 걸리면 `waf-extra-rules` 다. **set-02만 Web ACL이 없다.**

## 복사할 파일

`waf-regional.tf` **또는** `waf-cloudfront.tf` 중 **하나만** 복사한다. 둘 다 복사하면 리소스 이름이 충돌한다.

| 앞단 | 복사할 파일 | 연결 방법 |
| --- | --- | --- |
| ALB / API Gateway | `waf-regional.tf` | `addon_waf_target_arn` 에 ARN 주입 (association 리소스가 붙인다) |
| CloudFront | `waf-cloudfront.tf` | 배포 리소스에 `web_acl_id` 한 줄 추가 (아래 2번) |

`variables.tf` 는 `variables-waf-addon.tf` 로 이름 바꿔 복사한다.

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_waf_name` | **필수** | Web ACL 이름. 과제지 명시 이름과 정확히 일치 |
| `addon_waf_rate_limit` | `100` | rate-based rule 임계 요청 수 (윈도당, IP 기준) |
| `addon_waf_rate_window_sec` | `60` | 평가 윈도(초). **60/120/300/600만 허용** |
| `addon_waf_target_arn` | `""` | 연결할 ALB / API Gateway ARN (REGIONAL 전용) |

## CHECK · RUN

```powershell
aws sts get-caller-identity   # 지급 계정인가
aws configure get region      # 과제지 리전인가
terraform fmt; terraform init; terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

## 0. Web ACL 자체의 output

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf  (없으면 새로 추가)
output "addon_waf_arn" {
  description = "Web ACL ARN — association / CloudFront web_acl_id 에 사용"
  value       = aws_wafv2_web_acl.addon.arn
}

output "addon_waf_id"   { value = aws_wafv2_web_acl.addon.id }
output "addon_waf_name" { value = aws_wafv2_web_acl.addon.name }
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 기존 Web ACL | 상태 |
| --- | --- | --- |
| set-02 | **없음** | 이 KIT으로 신규 생성. 위 output 블록 추가 |
| set-03 | `aws_wafv2_web_acl.wsc2026` (CLOUDFRONT) | output **없음** — 아래 블록으로 기존 것을 노출 |
| set-07 | `aws_wafv2_web_acl.unicorn` (CLOUDFRONT) | output **없음** — 아래 블록으로 기존 것을 노출 |

```hcl
# 파일: set-03/task-1/terraform/outputs.tf
output "waf_arn"  { value = aws_wafv2_web_acl.wsc2026.arn }
output "waf_id"   { value = aws_wafv2_web_acl.wsc2026.id }
output "waf_name" { value = aws_wafv2_web_acl.wsc2026.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "waf_arn"  { value = aws_wafv2_web_acl.unicorn.arn }
output "waf_id"   { value = aws_wafv2_web_acl.unicorn.id }
output "waf_name" { value = aws_wafv2_web_acl.unicorn.name }
```

```powershell
terraform output -raw addon_waf_arn     # 신규(set-02)
terraform output -raw waf_arn           # 기존(set-03/set-07)

# CLOUDFRONT scope 조회는 반드시 us-east-1
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[].[Name,Id]" --output table
aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[].[Name,Id]" --output table
```
</details>

## 1. REGIONAL — ALB / API Gateway에 붙이기

```hcl
# 파일: set-XX/task-1/terraform/waf-regional.tf   (KIT에서 복사됨)
resource "aws_wafv2_web_acl_association" "addon" {
  resource_arn = var.addon_waf_target_arn
  web_acl_arn  = aws_wafv2_web_acl.addon.arn
}
```

<details><summary><b>값 뽑기 — 세트별 (ALB ARN을 tfvars로 주입)</b></summary>

| 세트 | 앱 ALB 리소스 주소 | ALB ARN output |
| --- | --- | --- |
| set-02 | `aws_lb.book` | **없음** — 아래 블록 추가 |
| set-03 | **Terraform ALB 없음** — LBC가 만든다. 아래 CLI로 찾는다 | — |
| set-07 | `aws_lb.app` (internal) | **없음** — 아래 블록 추가 |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_alb_arn" { value = aws_lb.book.arn }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_alb_arn" { value = aws_lb.app.arn }
```

```powershell
# set-02 / set-07
terraform output -raw app_alb_arn
# → terraform.tfvars 의 addon_waf_target_arn 에 넣거나 직접 참조로 바꾼다

# set-03 — LBC 가 만든 ALB 라 state 에 없다
aws elbv2 describe-load-balancers `
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,LoadBalancerArn]" --output table
```

set-03처럼 LBC가 만든 ALB에는 **Terraform association 대신 Ingress 어노테이션**을 쓴다 (LBC 동기화 때 association이 벗겨진다):

```yaml
# 파일: set-03/task-1/k8s/app/05-ingress.yaml   (metadata.annotations 안)
alb.ingress.kubernetes.io/wafv2-acl-arn: "<terraform output -raw waf_arn 값>"
```
</details>

## 2. CLOUDFRONT — 배포에 붙이기

```hcl
# 파일: set-XX/task-1/terraform/cloudfront.tf
# 기존 aws_cloudfront_distribution 리소스 블록 *안에* 한 줄 추가
web_acl_id = aws_wafv2_web_acl.addon.arn
```

전제 — us-east-1 provider alias가 없으면 추가한다:

```hcl
# 파일: set-XX/task-1/terraform/versions.tf   (set-03 은 providers.tf)
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | CloudFront 리소스 주소 | alias 선언 파일 | `use1` alias | 도메인 output |
| --- | --- | --- | --- | --- |
| set-02 | `aws_cloudfront_distribution.cdn` | `versions.tf` | **없음** — 추가 필요 | `cloudfront_domain` (있음) |
| set-03 | `aws_cloudfront_distribution.cdn[0]` (`enable_cdn` count) | `providers.tf` | **이미 있음** (WAF가 CLOUDFRONT) | `cloudfront_domain` (있음, count면 null) |
| set-07 | `aws_cloudfront_distribution.cdn` | `versions.tf` | **이미 있음** (WAF·KMS replica) | `cloudfront_domain` (있음) |

중복 선언하면 apply가 실패한다 — 먼저 확인:

```powershell
Select-String -Path versions.tf,providers.tf -Pattern 'alias\s*=\s*"use1"'
```

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "cloudfront_id" { value = aws_cloudfront_distribution.cdn.id }   # set-03 은 cdn[0].id
```

```powershell
terraform output -raw cloudfront_domain
aws cloudfront get-distribution-config --id (terraform output -raw cloudfront_id) `
  --query "DistributionConfig.WebACLId"
```
</details>

## 3. 로깅 (요구될 때만)

```hcl
# 파일: set-XX/task-1/terraform/waf.tf
resource "aws_cloudwatch_log_group" "addon_waf" {
  provider          = aws.use1                          # CLOUDFRONT scope 면 필수
  name              = "aws-waf-logs-${var.addon_waf_name}"   # 접두어 강제
  retention_in_days = 30
}

resource "aws_wafv2_web_acl_logging_configuration" "addon" {
  provider                = aws.use1
  resource_arn            = aws_wafv2_web_acl.addon.arn
  log_destination_configs = [trimsuffix(aws_cloudwatch_log_group.addon_waf.arn, ":*")]
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 기존 WAF 로깅 |
| --- | --- |
| set-02 | 없음 (WAF 자체가 없음) |
| set-03 | **없음** — Web ACL은 있으나 로깅 미구성. 이 블록이 필요하다 |
| set-07 | `aws_cloudwatch_log_group.waf`(`aws-waf-logs-unicorn`) + `aws_cloudwatch_log_resource_policy.waf` + `aws_wafv2_web_acl_logging_configuration.unicorn` **전부 있음** |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "waf_log_group" { value = aws_cloudwatch_log_group.addon_waf.name }   # set-07 은 aws_cloudwatch_log_group.waf.name
```

```powershell
# CLOUDFRONT 로그 그룹은 us-east-1 에 있다
aws logs tail (terraform output -raw waf_log_group) --region us-east-1 --since 10m
aws wafv2 get-logging-configuration --resource-arn (terraform output -raw waf_arn) --region us-east-1
```

**로깅이 요구되지 않으면 이 블록을 지운다** — 불필요 리소스 감점 대상이다.
</details>

## 과제지 변형 대응

| 과제지 문장 | 복사 원본 |
| --- | --- |
| 차단 응답 본문 지정 ("403 + 지정 문자열") | set-07 task-1 `waf.tf` 의 `custom_response_body` + `rule_action_override` |
| 특정 경로만 검사 / 미제공 경로는 404 유지 | task-3 `waf.tf` 의 regex_pattern_set + `scope_down_statement` |
| SQLi 룰셋 | `AWSManagedRulesSQLiRuleSet` (task-3 `waf.tf`). base64 우회까지면 task-3 `base64-sqli` 커스텀 룰 |
| 관리형 룰 그룹 · Geo · Rate limit 추가 | [waf-extra-rules](../waf-extra-rules/README.md) |

## VERIFY

```powershell
aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[].{Name:Name,Id:Id}"
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[].Name"

$d = terraform output -raw cloudfront_domain
curl.exe -s -o NUL -w "%{http_code}`n" "https://$d/?id=1' OR 1=1--"   # 403
```

## TROUBLESHOOT

- **CLOUDFRONT scope 리소스는 전부 us-east-1.** provider alias 누락 시 `plan`은 통과하고 `apply`에서 `WAFInvalidParameterException`이 난다.
- 로그 그룹 이름은 **`aws-waf-logs-` 접두어 강제**. `log_destination_configs` 에 `:*` 붙은 ARN은 거부된다.
- rate limit `evaluation_window_sec` 는 **60/120/300/600만 허용**.
- managed rule group은 `and_statement` 로 감쌀 수 없다 — 경로 한정은 `scope_down_statement` 만 가능.
- LBC가 만든 ALB(set-03)에 Terraform association을 걸면 벗겨진다. Ingress 어노테이션을 쓴다.

---

## 막히면 여는 순서

인자 이름이나 조합에서 막히면 ① 위 **실전 구현**(이미 apply 가 통과한 코드) → ② 로컬 스키마 명령 → ③ 공식 문서 순으로 연다. 대회장 인터넷은 공식 문서까지 열려 있다. 그래도 ①②를 먼저 여는 건 브라우저보다 빠르고, 블로그에서 인자 이름을 베껴 프로바이더·차트 버전이 어긋나는 일이 없어서다.

```powershell
terraform providers schema -json | jq '.provider_schemas[].resource_schemas["<리소스타입>"].block.attributes | keys'
aws <서비스> <명령> help
kubectl explain <리소스>.spec --recursive
```

리소스별 공식 문서 주소·이 저장소의 구현 위치·흔히 막히는 인자는 [DOC-LINKS 4절 리소스별 색인](../../../DOC-LINKS.md#4-리소스별-색인)에 한 줄씩 있다. 리소스 타입(`aws_s3_bucket` 등)으로 Ctrl+F 한다.

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), 세트별 리소스 주소는 [대조표](../../../KIT-INDEX.md#세트별-리소스-주소-대조표-task-1)(표에 없는 세트는 [주소 찾는 명령](../../../KIT-INDEX.md#표에-없는-세트는-직접-찾는다)), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
