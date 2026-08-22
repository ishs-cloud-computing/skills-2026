# cw-logs-insights 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

CloudWatch Logs Insights 저장 쿼리(`aws_cloudwatch_query_definition`) 묶음 — 앱 로그(status·경로·지연) 5개 + WAF 로그(룰·UA·경로·IP 별 BLOCK 집계) 6개.
task-3 "로그 쿼리 추가" 류 문항, 1과제 Observability 옵션(로그 분석 형), set-08/09 task-1 ECS 로그 분석 추가 문항에 대응한다.
쿼리 원문은 아래 "블록" 절 — Terraform 없이 콘솔에 붙여 넣어도 된다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 0개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_cwli_name_prefix` | `"skills"` | 저장 쿼리 이름 접두. 콘솔에는 <접두>/app/..., <접두>/waf/... 폴더로 보인다. 과제지가 이름을 지정하면 그 값 |
| `addon_cwli_app_log_group_names` | `[]` | 앱 로그 쿼리 대상 로그 그룹 (ECS awslogs `/ecs/<앱>` · Container Insights `/aws/containerinsights/<클러스터>/application` 등). 비어 있으면 앱 쿼리를 만들지 않는다 |
| `addon_cwli_waf_log_group_names` | `[]` | WAF 로그 그룹 (`aws-waf-logs-*`). CLOUDFRONT scope 는 us-east-1 에 있으므로 쿼리 정의도 aws.use1 로 만든다. 비어 있으면 WAF 쿼리를 만들지 않는다 |

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

## 파일

- `cw-logs-insights.tf` — 쿼리 원문(locals) + `aws_cloudwatch_query_definition` 2묶음(앱: 기본 리전 / WAF: `aws.use1`)
- `variables.tf` — `addon_cwli_*` 변수. 로그 그룹 이름 2종(list) + 이름 접두

## 부착 절차

1. 두 파일을 `set-XX/task-Y/terraform/` 으로 복사한다. WAF 쿼리를 쓰면 provider alias `use1` 필요 — 없으면 `versions.tf` 에 추가(waf/README 의 블록). REGIONAL scope WAF(로그 그룹이 기본 리전)면 `addon_waf` 리소스의 `provider = aws.use1` 줄을 지운다.
2. `terraform.tfvars` 에 로그 그룹 이름을 넣는다. 빈 list 인 묶음은 만들지 않는다. 기존 리소스를 직접 참조하려면 `var.addon_cwli_app_log_group_names` 를 `[aws_cloudwatch_log_group.<기존>.name]` 으로 바꾼다.

   ```hcl
   addon_cwli_name_prefix         = "skills"
   addon_cwli_app_log_group_names = ["/ecs/skills-app"]                       # EKS: ["/aws/containerinsights/skills-eks/application"]
   addon_cwli_waf_log_group_names = ["aws-waf-logs-skills-waf"]               # us-east-1 (CLOUDFRONT)
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증 — 저장 쿼리 존재 + 실제 실행:

   ```powershell
   aws logs describe-query-definitions --query-definition-name-prefix skills/ --query 'queryDefinitions[].name'
   aws logs describe-query-definitions --query-definition-name-prefix skills/waf --region us-east-1 --query 'queryDefinitions[].name'

   # 실행 (콘솔: CloudWatch → Logs Insights → Saved queries → skills/...). CLI:
   $q = aws logs start-query --log-group-name /ecs/skills-app --start-time ([DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeSeconds()) --end-time ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) --query-string 'parse @message /status=(?<status>[0-9]{3})/ | filter ispresent(status) | stats count() as cnt by status | sort status asc' --query queryId --output text
   aws logs get-query-results --query-id $q
   ```

## 블록

콘솔 Logs Insights 에 그대로 붙여 넣는 원문. `.tf` 의 locals 와 같다.

### 앱 로그 (`/ecs/<앱>` · `/aws/containerinsights/<클러스터>/application`) — 형식 `... path=/x status=404 duration=12 ...`

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

JSON 로그(`{"status":404,"path":"/x","duration_ms":12}`)면 parse 없이 필드를 바로 쓴다 — `filter status >= 500 | stats count() by path`. Container Insights 는 앱 stdout 이 `log` 필드 안에 문자열로 들어가므로 위 regex parse 가 그대로 맞는다.

### WAF 로그 (`aws-waf-logs-*`, CLOUDFRONT 는 us-east-1)

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

UA 별 BLOCK (UA 는 `httpRequest.headers[]` 안이라 parse 필수):

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

COUNT 룰 매칭(승격 판단용 — top-level `action` 에 COUNT 는 없다):

```
filter ispresent(nonTerminatingMatchingRules.0.ruleId)
| stats count() as cnt by nonTerminatingMatchingRules.0.ruleId, action
| sort cnt desc
```

조사용 변형: 위 쿼리의 `filter action = "BLOCK"` 뒤에 `and httpRequest.uri like /^\/v1\//`(정상 경로만) 또는 `and ua like /gobuster|zap|wpscan|sqlmap|nikto/` 를 이어 붙인다. regex 리터럴 안의 `/` 는 `\/`.

## TROUBLESHOOT — 이 KIT 고유 함정
- 전부 신규 리소스 — 기존 리소스 재생성 없음. `name` 변경은 in-place(query_definition_id 유지).
- **쿼리 정의는 리전 리소스다.** 로그 그룹이 있는 리전에 만들어야 콘솔 Saved queries 에 보인다 — CLOUDFRONT WAF 로그는 us-east-1 이라 `aws.use1`.
- `log_group_names` 의 로그 그룹은 apply 시점에 없어도 생성은 된다(검증 안 함). 단 실행 시 로그 그룹이 없으면 `ResourceNotFoundException`.
- 앱 로그 형식은 세트마다 다르다 — 기본 regex 는 set-08 앱(`path=/x status=404 duration=...`) 실측. 먼저 `fields @message | limit 5` 로 한 줄 보고 parse 를 맞춘다. `duration` 단위(ms/s)·접미사 유무는 **확인 필요** — 숫자 뒤에 `ms` 가 붙으면 `[0-9.]+` 가 숫자만 잡으므로 그대로 동작한다.
- 문법 함정(task-3 실측): `stats ... by` 한 명령을 여러 줄로 나누면 `MalformedQueryException` — 명령 단위로 한 줄. `sort bin(5m)` 불가 → `by bin(5m) as t | sort t asc`. regex 리터럴 `/.../` 안의 `/` 는 `\/` 이스케이프.
- WAF 로그에 요청 body 는 없다. body 매칭 룰은 `terminatingRuleMatchDetails`/`matchedData` 토큰으로만 본다. `count-rules` 쿼리는 `nonTerminatingMatchingRules.0`(첫 요소)만 센다 — 다중 매칭 요청은 누락.
- ALB access log 는 S3 전용(Athena 대상) — Logs Insights 로 못 본다. 과제지가 "ALB 로그 쿼리" 를 요구하면 ALB 앞단이 아니라 앱 로그(ECS awslogs / Container Insights) 를 대상으로 잡는다.
- 과제지가 저장 쿼리 이름을 지정하면 `addon_cwli_name_prefix` 가 아니라 locals 의 key 까지 그 이름으로 맞춘다(이름 정확 일치). `/` 는 콘솔 폴더 구분자다.
- 저장 쿼리 파라미터(`{{param}}`)는 콘솔 전용 — `query_string` 에 넣으면 그대로 문자열이라 API 실행이 깨진다. 조사값은 수동 치환.

## 실전 구현 (참고용)

- task-3 `NOTES.md` "Logs Insights 쿼리 세트" — WAF 쿼리 라이브 검증 기록 (쿼리 파일은 삭제됨, 원문은 이 README 가 재구성본)
- task-3 `terraform/waf.tf` — WAF 로그 그룹(us-east-1) + logging_configuration
- set-08 task-1 `terraform/cloudwatch.tf` — 앱 로그 형식·메트릭 필터 패턴(`%status=4[0-9][0-9]%`)
