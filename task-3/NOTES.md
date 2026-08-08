# task-3 NOTES

## WAF 로그 분석 (demo/, 연습 세션 2026-08-08)

`demo/*.gz`는 연습 빌드에 트래픽을 받은 뒤 CloudWatch Logs에서 export한 WAF 로그다.
**당일 경로·UA·IP는 100% 달라진다** — 아래 수치는 쿼리·룰의 판별 *패턴*을 검증한 근거이지, 당일 기준값이 아니다.

- 원본: us-east-1 로그 그룹 `aws-waf-logs-demo` (콘솔 생성 Web ACL `CreatedByCloudFront-ac43a69e`, repo `terraform/waf.tf`의 `skills-waf`와 다름)
- 형식: CloudWatch export = `<타임스탬프> <JSON>` 줄. 파싱: `zcat demo/*.gz | sed 's/^[^ ]* //' | jq`
- 총 720,319건 (05:56–11:12 UTC) = ALLOW 662,869 + BLOCK 57,450. export가 라이브 로그 그룹보다 2건 적음(경계 누락, 무시 가능)
- top-level `action`에 COUNT는 **없다**. Count 룰 매칭은 `nonTerminatingMatchingRules[]`에만 남는다 (해당 요청 35,010건 = ALLOW 24,081 + BLOCK 10,929)

### 필드 실측 (문서 대비)

- 전 레코드 존재: `timestamp, formatVersion, webaclId, terminatingRuleId, terminatingRuleType, action, terminatingRuleMatchDetails[], httpSourceName, httpSourceId, ruleGroupList[], rateBasedRuleList, nonTerminatingMatchingRules[], requestHeadersInserted, responseCodeSent, httpRequest.{clientIp, country, headers[], uri, args, httpVersion, httpMethod, requestId, fragment, scheme, host}`
- 일부 존재: `labels` 499,143 · `requestBodySize(-InspectedByWAF)` 407,823 · `ja3/ja4Fingerprint` 41 · `oversizeFields` 1
- 항상 비어있음: `rateBasedRuleList=[]`, `requestHeadersInserted=null`, `responseCodeSent=null` (rate-based 룰·커스텀 응답 미사용이라)
- **요청 body는 로그에 없다.** BODY 매칭 룰은 `ruleMatchDetails.matchedData` 토큰으로만 판정해야 한다
- UA는 `httpRequest.headers[]` 안이라 QL에서 직접 필드 접근 불가 → `parse @message '"name":"User-Agent","value":"*"' as ua` 로 추출 (검증 완료)

### 트래픽 구성과 악성 판별 기준

축별 판별력 (demo 실측):

| 축 | 판별력 | 근거 |
|---|---|---|
| 페이로드(args) | **강** | LFI `php://filter/...=/etc/passwd` → /v1/product 7,003건(PHP룰 3,474 + Linux룰 3,362 차단, 167 통과). SQLi `id=2' OR '1'='1` → /v1/product 7,001건. body SQLi(`OR 1=1`) → POST /v1/user 6,999건 count-통과 |
| 경로(uri) | **강** | `/.svn/entries`·`/dump.sql` 각 7,003건 — 정상 라우팅과 교집합 없음 |
| UA | **강** | 스캐너 UA는 `gobuster/3.6`·`ZAP/2.14.0`·`WPScan v3.8.22` 각 ~7,000건. 부하 생성기는 브라우저형 Chrome UA(698,819건)로 완전 분리 |
| IP | **없음** | 전체의 99.4%(715,958건)가 단일 IPv6 — 부하 생성기와 공격이 같은 소스. IP 기반 차단은 채점 트래픽 동반 사살 |
| country | **없음** | 사실상 전량 KR |

### 오탐 실증 (연습 세션의 사고)

커스텀 룰 `Block-SQLi-In-Args`(SQLi match, QUERY_STRING, sensitivity **HIGH**)가 08:00–08:30에만 활성화됐는데,
그 창에서 정상 채점 트래픽 `email=grade-...@example.org&requestid=...&uuid=<uuid>` **24,220건을 차단**했다
(해당 창 grade 트래픽의 80%). matchedData가 `["email","=","grade","example.org","=","999999999999"]` — HIGH sensitivity
토크나이저가 이메일·숫자 파라미터를 SQLi로 판정한 것. 차단 27,559건의 구성: 오탐 24,220 + 스캐너 더미쿼리 2,492 + 실제 SQLi 846.
→ **처리량이 채점인 이 과제에서 sensitivity HIGH 커스텀 SQLi 룰은 금지.**

Count 매칭 중 오탐/실탐 판정:
- `SQLi_QUERYARGUMENTS` 6,155·`SQLi_BODY` 6,999 count-통과 = **실제 공격이 통과한 것** (demo ACL이 SQLiRuleSet을 count로 운용해서). repo `waf.tf`는 `override none`이라 차단됨 — 올바른 설정
- `CrossSiteScripting_BODY` 7,002 — body 미로깅이라 payload 확인 불가, matchedData 토큰으로만 판정
- `UserAgent_BadBots_HEADER`(CommonRuleSet) — 스캐너 UA에 반응. CommonRuleSet 전체 승격 시 다른 sub-rule 오탐 위험은 ARCHITECTURE.md 기존 방침(제외) 유지

## WAF 룰 설계안 (설계만 — terraform 미반영)

| 룰 | 매칭 조건(패턴) | 액션 | 근거 (demo) | 오탐 회피 | 당일 값이 다를 때 바꿀 것 |
|---|---|---|---|---|---|
| Block-Malicious-URI-Paths | 정상 라우팅 밖에서 반복 스캔되는 경로 prefix 목록 (URI regex/byte match) | BLOCK | 스캔 경로 14,006건 중 10,426 차단, 정상 경로 교집합 0 | 화이트리스트 밖 경로만 지정 (13번 쿼리로 확인 후) | 쿼리 13으로 당일 스캔 경로 확인 → 경로 목록 교체 |
| Block-Scanner-User-Agents | 스캐너 도구 UA substring 목록 (gobuster·wpscan·zap·sqlmap·nikto 류) | BLOCK | 203건 차단, 부하 생성기 UA(브라우저형)와 불교차 | 쿼리 12로 부하 생성기 UA 먼저 확인 후 목록 확정 | UA 목록 교체 |
| AWSManagedRulesBotControlRuleSet | managed (non-browser UA signal 등) | **COUNT로 시작 → 부하 생성기 UA가 브라우저형임을 확인한 뒤 BLOCK 승격** | 12,426건 전량 스캐너 차단, 부하 생성기 피해 0 | 부하 생성기가 k6 기본 UA(non-browser)면 승격 금지 — 채점 트래픽 직접 차단 | 쿼리 12·04로 판정 후 승격 여부 결정 |
| AWSManagedRulesSQLiRuleSet | managed (기존 skills-waf에 있음) | BLOCK (`override none` 유지) | count 운용 시 SQLi 13,154건 통과 실증 → block이 맞음 | 기본 sensitivity(LOW) 유지, 쿼리 15로 오탐 감시 | 오탐 발생 sub-rule만 count 강등 |
| Block-SQLi-In-Args (demo 커스텀) | — | **포팅 금지** | sensitivity HIGH가 정상 트래픽 24,220건 차단 | managed SQLiRuleSet로 갈음 | — |
| rate-based rule | — | **보류** | 공격·채점 트래픽이 단일 IP 공유(99.4%) → IP 집계 차단 불가 | — | 당일 소스 IP 분리가 확인되면 재검토 |
| CommonRuleSet | managed | 기존 방침 유지 (미포함, 당일 필요 시 ARCHITECTURE.md의 ua-only count 블록) | XSS_BODY 7,002 count — body 미로깅으로 판정 불가 | — | — |

로깅 설정안 (설계만): us-east-1에 `aws-waf-logs-<prefix>` 로그 그룹(CLOUDFRONT scope 로깅은 us-east-1 필수) + retention 지정,
`aws_wafv2_web_acl_logging_configuration`으로 `skills-waf`에 연결. 볼륨이 부담이면 logging filter로 ALLOW 드롭하고 BLOCK/COUNT만 보존
— 단 그러면 쿼리 01(추이)·10(전수 피벗)이 반쪽이 되므로 기본은 전량 보존.

## Logs Insights 쿼리 세트 (queries/)

상시 01–04, 조사 퍼널 10→11/12/13→14→15. 각 파일 상단 주석에 언제/입력/다음 명시.
조사 대상값(IP·UA·룰명)은 저장 쿼리 파라미터 `{{target_ip}}`·`{{target_ua}}`·`{{target_rule}}` — 콘솔에서 저장 쿼리로 등록하면
`$이름(target_ip="x.x.x.x")` 형태로 실행, 직접 붙여넣을 땐 수동 치환.
정상 경로 목록 `<NORMAL_PATHS>`만은 regex 리터럴이라 파라미터화 불가 → 본문 한 줄 수동 치환 (13·15 주석에 예시).

### 검증 결과 (라이브 Logs Insights 실행 + jq 대조, 전 쿼리 일치)

검증 명령: 쿼리를 `aws logs start-query`(로그 그룹 `aws-waf-logs-demo`, us-east-1)로 실행하고, 같은 집계를 `zcat demo/*.gz | sed 's/^[^ ]* //' | jq`로 재현해 대조.

| 쿼리 | 대조 지점 | 결과 |
|---|---|---|
| 01 | action 합계 | live 720,321 = jq 720,319 + export 누락 2건 ✓ |
| 02 | 룰별 BLOCK 6종 | 전부 일치 (27,559 / 12,426 / 10,426 / 3,474 / 3,362 / 203) ✓ |
| 03 | 상위 차단 IP 5종 | 일치 (57,223 / 57 / 35 / 28 / 20) ✓ |
| 04 | Count룰×action 4행 | 일치 (13,160 / 10,921 / 10,083 / 846) ✓ |
| 10 | 최대 IP requests | 715,958 일치 ✓ (count_distinct는 근사치) |
| 11 | IP 175.127.107.18 합계 | 625 일치 ✓ |
| 12 | UA "gobuster" 합계 | 7,001 (차단 5,041) 일치 ✓ |
| 13 | 비정상 경로 상위 4행 | 일치, 총합 live +2건 = 01과 동일 원인 ✓ |
| 15 | 정상 경로 BLOCK 6행 | 전부 일치, 13과 합치면 BLOCK 57,450 완전 분할 ✓ |

문법 함정 (실측): `stats ... by`를 여러 줄로 나누면 MalformedQueryException — 명령 단위로 한 줄 유지.
`sort bin(5m)` 불가 → `by bin(5m) as t | sort t asc`. regex 리터럴 `/.../ ` 안의 `/`는 `\/` 이스케이프 필수.

## 보류 항목

- `<NORMAL_PATHS>`의 저장 쿼리 파라미터화: `{{param}}`은 문자열 치환이라 regex 리터럴 자리에 쓸 수 있는지 문서로 확인 안 됨 → 수동 치환으로 운용
- 쿼리 04·14는 `nonTerminatingMatchingRules.0`(첫 요소)만 본다. 한 요청이 여러 Count 룰에 걸리면 두 번째 이후는 집계 누락 — demo에선 다중 매칭이 드물어 오차 없음, 필요 시 `unnest` 검토
- 앱 컨테이너 stdout/stderr → CloudWatch 수집 대안: `amazon-cloudwatch-observability` addon 제거(사용자 결정)로 앱 로그는 `kubectl logs`로만 확인. 로그 기반 운영 채점에 CloudWatch 앱 로그가 필요해지면 Fluent Bit 단독 배포 검토
- demo ACL(콘솔 생성, 커스텀 룰 포함)과 repo `waf.tf`(`skills-waf`)의 차이는 위 룰 설계안으로만 수렴 — terraform 반영은 당일 판단

## 문서 근거

- WAF 로그 필드: https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html
- Logs Insights QL 문법: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html
- 저장 쿼리 파라미터 (`{{param}}`): https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_Insights-Saving-Queries.html
- WAF 로그의 CloudWatch 분석 패턴 (nested 필드·parse): https://aws.amazon.com/blogs/mt/analyzing-aws-waf-logs-in-amazon-cloudwatch-logs/
