# WAF 부착 스니펫

`waf-regional.tf` **또는** `waf-cloudfront.tf` 중 하나 + `variables.tf` 를
`set-XX/task-1/terraform/` 으로 복사한다. 둘 다 복사하면 리소스 이름이 충돌한다.

## scope 선택

| 앞단 | 파일 | 연결 방법 |
| --- | --- | --- |
| ALB / API Gateway | `waf-regional.tf` | `addon_waf_target_arn` 변수에 ARN 주입 (association 리소스) |
| CloudFront | `waf-cloudfront.tf` | 배포 리소스에 `web_acl_id = aws_wafv2_web_acl.addon.arn` 한 줄 추가 |

## CLOUDFRONT 전제 조건

versions.tf 에 us-east-1 alias 가 없으면 추가한다:

```hcl
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}
```

set-07·set-05 task-1 은 이미 있다. 기존에 `aws.use1` 별칭이 다른 이름이면 스니펫 쪽을 맞춘다.

## 과제지 변형 대응

- **차단 응답 본문 지정** ("403 + 지정 문자열"): set-07 task-1 `waf.tf` 의
  `custom_response_body` + `rule_action_override` 패턴을 복사한다.
- **특정 경로만 검사 / 미제공 경로 404 유지**: task-3 `waf.tf` 의
  regex_pattern_set + `scope_down_statement` 패턴을 복사한다.
- **SQLi 룰셋 요구**: managed rule `AWSManagedRulesSQLiRuleSet` 룰 블록을 추가한다
  (task-3 waf.tf 에 있음). base64 우회까지 막으라면 task-3 의 `base64-sqli` 커스텀 룰 참고.
- **로깅 미요구**: 로그 그룹·리소스 정책·logging_configuration 블록을 지운다
  (불필요 리소스 감점 방지).

## 함정

- CLOUDFRONT scope 리소스(WebACL·로그 그룹)는 전부 us-east-1. provider 누락 시
  plan 은 통과하고 apply 에서 WAFInvalidParameterException 이 난다.
- 로그 그룹 이름은 `aws-waf-logs-` 접두어 강제.
- rate limit 의 `evaluation_window_sec` 는 60/120/300/600 만 허용.
- managed rule group 은 `and_statement` 로 감쌀 수 없다 — 경로 한정은 `scope_down_statement` 만 가능.
