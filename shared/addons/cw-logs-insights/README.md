# CloudWatch Logs Insights 부착 KIT

저장 쿼리(`aws_cloudwatch_query_definition`) 묶음 — 앱 로그(status·경로·지연) 5개 + WAF 로그(룰·UA·경로·IP별 BLOCK) 6개. 쿼리 원문은 아래 블록에 있어 콘솔에 그대로 붙여 넣어도 된다.

## 이 KIT이 맞나

- 과제지에 **"로그 쿼리"·"저장된 쿼리"·"로그 분석"** → 맞다.
- **경보** → [cw-alarms](../cw-alarms/README.md) · **대시보드** → [cw-dashboard](../cw-dashboard/README.md).
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 쿼리 대상 로그 그룹

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 앱 로그 그룹 | `aws_cloudwatch_log_group.pod_logs` | `.book_app` | `.book_app` |
| Lambda 로그 그룹 | `.book_lambda` | `.book_function` | `.get_booking` |
| WAF 로그 그룹 | **없음** (WAF 자체 없음) | **없음** (로깅 미구성) | `aws_cloudwatch_log_group.waf` = `aws-waf-logs-unicorn` (**us-east-1**) |
| 앱 로그 수집 | Fluent Bit (`k8s/monitoring/`) | Fluent Bit (`k8s/logging/`) | Fluent Bit (`k8s/logging/`) |
| 기존 저장 쿼리 | **없음** | **없음** | **없음** |

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `cw-logs-insights.tf` | `set-XX/task-1/terraform/` | 쿼리 원문(locals) + `aws_cloudwatch_query_definition` 2묶음 (앱: 기본 리전 / WAF: `aws.use1`) |
| `variables.tf` | `variables-cwli-addon.tf` | `addon_cwli_*` 변수 |

WAF 쿼리를 쓰면 provider alias `use1` 이 필요하다 — set-03·set-07은 **이미 있고**, set-02는 없으니 추가한다. REGIONAL scope WAF면 `provider = aws.use1` 줄을 지운다.

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_cwli_name_prefix` | `"skills"` | 저장 쿼리 이름 접두. 콘솔에 `<접두>/app/...` 폴더로 보인다. `/` 는 폴더 구분자 |
| `addon_cwli_app_log_group_names` | `[]` | 앱 쿼리 대상. 비어 있으면 앱 쿼리를 만들지 않는다 |
| `addon_cwli_waf_log_group_names` | `[]` | WAF 로그 그룹(`aws-waf-logs-*`). 비어 있으면 WAF 쿼리를 만들지 않는다 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## 0. 대상 로그 그룹 지정

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_cwli_name_prefix         = "skills"
addon_cwli_app_log_group_names = ["/aws/containerinsights/wskorea26-cluster/application"]
addon_cwli_waf_log_group_names = []     # set-07 만 ["aws-waf-logs-unicorn"]
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

tfvars에 손으로 적지 말고 output에서 뽑는다:

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_log_group"    { value = aws_cloudwatch_log_group.pod_logs.name }
output "lambda_log_group" { value = aws_cloudwatch_log_group.book_lambda.name }

# 파일: set-03/task-1/terraform/outputs.tf   (app_log_group 은 이미 있다)
output "lambda_log_group" { value = aws_cloudwatch_log_group.book_function.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_log_group"    { value = aws_cloudwatch_log_group.book_app.name }
output "lambda_log_group" { value = aws_cloudwatch_log_group.get_booking.name }
output "waf_log_group"    { value = aws_cloudwatch_log_group.waf.name }
```

```powershell
terraform output -raw app_log_group
terraform output -raw lambda_log_group
terraform output -raw waf_log_group          # set-07 만

# 계정에 실제로 있는 로그 그룹 목록 (Container Insights 를 켰다면 여기 뜬다)
aws logs describe-log-groups --query "logGroups[].logGroupName" --output table
aws logs describe-log-groups --region us-east-1 `
  --log-group-name-prefix aws-waf-logs- --query "logGroups[].logGroupName"
```

또는 `.tf` 안에서 직접 참조로 바꾼다:

```hcl
# 파일: set-XX/task-1/terraform/cw-logs-insights.tf
log_group_names = [aws_cloudwatch_log_group.book_app.name]   # ← 세트별 주소
```
</details>

## 1. 앱 로그 쿼리 — 형식 `... path=/x status=404 duration=12 ...`

status 분포:

```
parse @message /status=(?<status>[0-9]{3})/
| filter ispresent(status)
| stats count() as cnt by status
| sort status asc
```

4xx/5xx 경로 상위:

```
parse @message /path=(?<path>[^ ]+) status=(?<status>[0-9]{3})/
| filter status like /^[45]/
| stats count() as cnt by status, path
| sort cnt desc
| limit 20
```

경로별 지연(avg·p95·max):

```
parse @message /path=(?<path>[^ ]+) status=(?<status>[0-9]{3}) duration=(?<duration>[0-9.]+)/
| filter ispresent(duration)
| stats count() as cnt, avg(duration) as avg_ms, pct(duration, 95) as p95_ms, max(duration) as max_ms by path
| sort p95_ms desc
```

5xx 추이(5분):

```
parse @message /status=(?<status>[0-9]{3})/
| filter status like /^5/
| stats count() as errors by bin(5m) as t
| sort t asc
```

오류 키워드 최근 100건:

```
filter @message like /(?i)(error|exception|panic|fatal|timeout)/
| fields @timestamp, @logStream, @message
| sort @timestamp desc
| limit 100
```

<details><summary><b>값 뽑기 — 세트별 (parse 를 맞추는 게 먼저다)</b></summary>

**앱 로그 형식은 세트마다 다르다.** 위 regex는 예시다 — 실제 한 줄을 먼저 본다:

```powershell
$lg = terraform output -raw app_log_group
aws logs tail $lg --since 15m | Select-Object -First 5

# 쿼리를 CLI 로 바로 실행해 본다
$q = aws logs start-query --log-group-name $lg `
  --start-time ([DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeSeconds()) `
  --end-time ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) `
  --query-string 'parse @message /status=(?<status>[0-9]{3})/ | filter ispresent(status) | stats count() as cnt by status | sort status asc' `
  --query queryId --output text
aws logs get-query-results --query-id $q

# 저장 쿼리가 만들어졌는지
aws logs describe-query-definitions --query-definition-name-prefix skills/ `
  --query "queryDefinitions[].name"
```

JSON 로그면 parse 없이 필드를 바로 쓴다 — `filter status >= 500 | stats count() by path`.

Fluent Bit이 CloudWatch로 보내는 경우 앱 stdout이 `log` 필드 안 문자열로 들어가므로 위 regex parse가 그대로 맞는다. Container Insights를 켰다면 `/aws/containerinsights/<클러스터>/application` 이 추가로 생긴다.
</details>

## 2. WAF 로그 쿼리 (`aws-waf-logs-*`, CLOUDFRONT는 us-east-1)

action 추이(5분):

```
stats count() as cnt by bin(5m) as t, action
| sort t asc
```

룰별 BLOCK:

```
filter action = "BLOCK"
| stats count() as cnt by terminatingRuleId
| sort cnt desc
```

UA별 BLOCK (UA는 `httpRequest.headers[]` 안이라 parse 필수):

```
filter action = "BLOCK"
| parse @message '"name":"User-Agent","value":"*"' as ua
| stats count() as cnt by ua
| sort cnt desc
| limit 20
```

경로별 BLOCK:

```
filter action = "BLOCK"
| stats count() as cnt by httpRequest.uri
| sort cnt desc
| limit 20
```

IP·국가별 BLOCK:

```
filter action = "BLOCK"
| stats count() as cnt by httpRequest.clientIp, httpRequest.country
| sort cnt desc
| limit 20
```

COUNT 룰 매칭(승격 판단용 — top-level `action` 에 COUNT는 없다):

```
filter ispresent(nonTerminatingMatchingRules.0.ruleId)
| stats count() as cnt by nonTerminatingMatchingRules.0.ruleId, action
| sort cnt desc
```

<details><summary><b>값 뽑기 — 세트별 (WAF 로그가 있는 세트는 set-07뿐)</b></summary>

| 세트 | WAF 로그 그룹 | 리전 | 준비 |
| --- | --- | --- | --- |
| set-02 | 없음 | — | [waf](../waf/README.md) 로 Web ACL부터 |
| set-03 | **없음** (Web ACL은 있으나 로깅 미구성) | us-east-1 | [waf](../waf/README.md) 3번으로 로깅 먼저 |
| set-07 | `aws-waf-logs-unicorn` | **us-east-1** | 그대로 쓸 수 있다 |

```powershell
# set-07
$waf = terraform output -raw waf_log_group
aws logs tail $waf --region us-east-1 --since 15m | Select-Object -First 3

$q = aws logs start-query --region us-east-1 --log-group-name $waf `
  --start-time ([DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeSeconds()) `
  --end-time ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) `
  --query-string 'filter action = "BLOCK" | stats count() as cnt by terminatingRuleId | sort cnt desc' `
  --query queryId --output text
aws logs get-query-results --query-id $q --region us-east-1

# 저장 쿼리도 us-east-1 에 만들어진다
aws logs describe-query-definitions --region us-east-1 `
  --query-definition-name-prefix skills/waf --query "queryDefinitions[].name"
```

**쿼리 정의는 리전 리소스다** — 로그 그룹이 있는 리전에 만들어야 콘솔 Saved queries에 보인다.

조사용 변형: `filter action = "BLOCK"` 뒤에 `and httpRequest.uri like /^\/v1\//` 또는 `and ua like /gobuster|zap|wpscan|sqlmap|nikto/` 를 이어 붙인다. regex 리터럴 안의 `/` 는 `\/`.
</details>

## VERIFY

```powershell
aws logs describe-query-definitions --query-definition-name-prefix skills/ --query "queryDefinitions[].name"
aws logs describe-query-definitions --query-definition-name-prefix skills/waf --region us-east-1 --query "queryDefinitions[].name"
```

콘솔: CloudWatch → Logs Insights → Saved queries → `skills/...`

## TROUBLESHOOT

- **쿼리 정의는 리전 리소스다.** CLOUDFRONT WAF 로그는 us-east-1이라 `aws.use1` 로 만든다.
- `log_group_names` 의 로그 그룹은 apply 시점에 없어도 생성은 된다(검증 안 함). 단 실행 시 없으면 `ResourceNotFoundException`.
- **앱 로그 형식은 세트마다 다르다.** `aws logs tail` 로 한 줄 보고 parse를 맞춘다.
- 문법 함정(task-3 실측): `stats ... by` 한 명령을 여러 줄로 나누면 `MalformedQueryException` — 명령 단위로 한 줄. `sort bin(5m)` 불가 → `by bin(5m) as t | sort t asc`. regex 리터럴 안 `/` 는 `\/`.
- WAF 로그에 **요청 body는 없다.** body 매칭 룰은 `terminatingRuleMatchDetails`/`matchedData` 토큰으로만 본다. `count-rules` 쿼리는 `nonTerminatingMatchingRules.0`(첫 요소)만 세므로 다중 매칭은 누락된다.
- **ALB access log는 S3 전용**(Athena 대상)이라 Logs Insights로 못 본다. "ALB 로그 쿼리" 요구면 앱 로그를 대상으로 잡는다.
- 과제지가 저장 쿼리 이름을 지정하면 `addon_cwli_name_prefix` 뿐 아니라 locals의 key까지 그 이름으로 맞춘다(이름 정확 일치).
- 저장 쿼리 파라미터(`{{param}}`)는 **콘솔 전용**이다. `query_string` 에 넣으면 API 실행이 깨진다.

## 실전 구현 (참고용)

- task-3 `NOTES.md` "Logs Insights 쿼리 세트" — WAF 쿼리 라이브 검증 기록
- task-3 `terraform/waf.tf` — WAF 로그 그룹(us-east-1) + logging_configuration
- set-07 task-1 `terraform/cloudwatch.tf` — WAF 로그 그룹 + 리소스 정책 (그대로 쿼리 대상)

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
