# task-3 NOTES

## WAF 로그 분석 (demo/, 연습 세션 2026-08-08)

`demo/*.gz`는 연습 빌드에 트래픽을 받은 뒤 CloudWatch Logs에서 export한 WAF 로그다.
**원본 파일(`demo/`)과 쿼리 파일(`queries/`)은 저장소에서 삭제됐다** — 아래 수치와 쿼리 설명만 근거로 남긴다.
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

로깅 설정 (**terraform 반영 완료**, `terraform/waf.tf`): us-east-1에 `aws-waf-logs-<waf 이름>` 로그 그룹(CLOUDFRONT scope 로깅은 us-east-1 필수, retention 1일) +
`aws_wafv2_web_acl_logging_configuration`으로 연결. 볼륨이 부담이면 logging filter로 ALLOW 드롭하고 BLOCK/COUNT만 보존
— 단 그러면 추이·전수 피벗 쿼리가 반쪽이 되므로 기본은 전량 보존.

## Logs Insights 쿼리 세트 (파일은 삭제됨 — 아래는 검증 기록)

상시 01–04, 조사 퍼널 10→11/12/13→14→15로 구성했었다. 각 파일 상단 주석에 언제/입력/다음 명시.
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

- 쿼리 파일을 저장소에 다시 둘지: 현재는 삭제 상태이고 당일 콘솔에서 직접 작성한다. `<NORMAL_PATHS>`의 저장 쿼리 파라미터화는 `{{param}}`이 문자열 치환이라 regex 리터럴 자리에 쓸 수 있는지 문서로 확인 안 됨 → 수동 치환으로 운용
- 쿼리 04·14는 `nonTerminatingMatchingRules.0`(첫 요소)만 본다. 한 요청이 여러 Count 룰에 걸리면 두 번째 이후는 집계 누락 — demo에선 다중 매칭이 드물어 오차 없음, 필요 시 `unnest` 검토
- 로그 볼륨을 더 줄이려면 `containerLogs.fluentBit.config.extraFiles`의 `dataplane-log.conf`·`host-log.conf`를 빈 문자열로 덮어써 dataplane/host 로그 그룹을 없애는 안 — **미검증**(빈 `@INCLUDE` 파일을 fluent-bit가 받아들이는지 확인 안 함). 현재는 기본값 유지
- demo ACL(콘솔 생성, 커스텀 룰 포함)과 repo `waf.tf`의 차이는 위 룰 설계안으로만 수렴 — 룰 자체의 terraform 반영은 당일 판단(로깅은 반영 완료)

## 결정 로그

### 2026-08-16 — base64 로 감싼 SQLi 가 관리형 룰을 그대로 통과 → `base64-sqli` 룰 추가

- **발단**: "managed SQLi 의 `uri_path` scope-down 이 쿼리스트링까지 적용되는 게 맞느냐" 검토.
  결론은 **맞다, 변경 불필요** — `uri_path` 는 쿼리스트링·fragment 를 포함하지 않는다
  ([Request components](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-fields-list.html)).
  라이브 실측으로도 경로가 같고 쿼리만 다른 두 요청이 갈렸다:
  `/v1/product?id=2` → 404(앱) vs `/v1/product?id=2'%20OR%20'1'='1` → 403(WAF, `server: CloudFront`).
  화이트리스트 정규식의 `$` 앵커가 성립하는 이유가 이거다.
  → **scope-down 에 `query_string` 을 추가하지 말 것. 앵커를 풀지 말 것.** 쿼리·바디의 SQLi 판정은
  scope-down 이 아니라 관리형 룰그룹(`SQLi_QUERYARGUMENTS`/`SQLi_BODY`)이 따로 한다.

- **거기서 드러난 진짜 구멍**: 같은 페이로드를 base64 로 감싸면 전부 통과한다.

  | 요청 | 결과 |
  |---|---|
  | `GET /v1/product?id=%27%20OR%20sleep%285%29--` | 403 ✅ |
  | `GET /v1/product?id=MScgT1IgJzEnPScx` (`1' OR '1'='1`) | **404** ❌ |
  | `POST /v1/product {"id":"<b64 SQLi>","name":"<b64 4096 A>"}` | **201** ❌ — DB 에 행 생성 |

- **원인**: 관리형 룰그룹은 자체 text transformation 이 **고정**이고 거기에 `BASE64_DECODE` 가 없다.
  밖에서 주입할 방법도 없다 — `scope_down_statement` 에 준 변환은
  *"not inherited by the containing managed rule group"* 이다. 관리형 룰그룹에서 조절 가능한 건
  버전 · rule action override · scope-down 셋뿐이다.

- **조치**: 커스텀 룰 `base64-sqli`(priority 40) 추가. `api_paths` 화이트리스트와 `and_statement`,
  그 안에 `or_statement` 로 (a) `all_query_arguments` + `URL_DECODE`→`BASE64_DECODE`,
  (b) `json_body`(VALUE, oversize CONTINUE) + `BASE64_DECODE`. 둘 다 **sensitivity LOW**.
  priority 30 은 당일 콘솔에서 붙일 `scanner-ua` 자리로 비워뒀다.

- **왜 이건 terraform 이고 UA 룰은 콘솔인가**: 값의 수명주기가 다르다. UA 목록은 당일 트래픽 로그를
  보고 정하는 실시간 튜닝 축이라 apply 왕복이 생기면 안 된다(아래 08-16 UA 항목). base64 차단은
  로그를 볼 필요가 없는 고정 룰이다 — `api_paths` 를 terraform 에 남긴 것과 같은 기준.

- **기각**: "연습 세션 로그(720,319건)에 base64 가 없었으니 안 막아도 된다" — **로그에 없다는 건
  그 세션에 안 나왔다는 뜻일 뿐 안 막을 근거가 아니다.** base64 로 감싼
  `' UNION SELECT username,password FROM users--` 는 인코딩만 다른 SQLi 다.

- **기각**: sensitivity HIGH — 정상 트래픽 24,220건 차단 사고(위 "오탐 실증")를 재현한다.
  룰을 빼는 게 아니라 LOW 로 넣고 실측 검증하는 쪽이 맞다.

- **오탐 감시**: `all_query_arguments` 범위가 유일한 리스크다. strict `BASE64_DECODE` 는 유효하지
  않은 입력에서 실패하므로 `uuid`(하이픈)·`email`(`@`·`.`)은 안 걸리고, 4의 배수 길이 숫자 파라미터는
  쓰레기 바이트로 디코드되나 SQL 토큰이 아니라 LOW 가 반응할 이유가 없다 — **추정이다**.
  CloudWatch 에서 `base64-sqli` 메트릭과 각 API availability 를 같이 보고, availability 가
  떨어지면 이 룰만 `count` 로 강등하거나 `single_query_argument { name = "id" }` 로 좁힌다.

- **부수 효과**: 검토용 POST 로 `product` 테이블에 `id='MScgT1IgJzEnPScx'` 행이 1건 생겼다.
  앱에 DELETE 엔드포인트가 없어 RDS 에서 직접 지워야 한다.

### 2026-08-16 — 없는 경로의 비정상 요청이 404 대신 403 으로 나가던 문제 → 전 룰 scope-down

- **문제**: 과제지 7절 예시는 `/v1/none` 으로의 *비정상* 요청도 404 를 요구한다. 그런데 403 은 WAF,
  404 는 ALB 리스너 기본액션이 내는 구조인데 **WAF 가 CloudFront 에 붙어 ALB 보다 앞**이다.
  `/v1/none?email='%20OR%201=1--` 는 WAF SQLi 룰이 먼저 물어 403 이 나갔다. 정확히 예시 케이스가 틀렸다.
- **원인**: 판정 순서가 "비정상 여부 먼저, 경로 존재 여부 나중" 이었다. 404 계층이 WAF 뒤에 있는 한
  WAF 가 무언가 차단하면 404 계층은 영영 실행되지 않는다.
- **조치**: `aws_wafv2_regex_pattern_set.api_paths`(존재하는 엔드포인트 화이트리스트)를 만들고
  두 관리형 룰의 `scope_down_statement` 로 걸었다. 화이트리스트 밖 경로는 WAF 가 판정 자체를 안 해
  오리진까지 가고 ALB 가 404 를 낸다. 순서가 "경로 존재 먼저" 로 뒤집힌다.
- **기각**: `and_statement` 로 managed rule group 을 감싸는 안 — WAF 가 managed rule group 의
  논리 statement 중첩을 허용하지 않는다. `scope_down_statement` 가 유일한 수단.
- **기각**: 없는 경로 전용 Block 룰에 `CustomResponse 404` 를 다는 안 — 룰이 늘 때마다 화이트리스트를
  두 벌 유지해야 하고, 404 의 출처가 ALB/WAF 두 곳으로 갈라진다.
- **부수 효과**: 위 룰 설계안의 `Block-Malicious-URI-Paths` 는 불필요해졌다. 스캔 경로(`/.svn/entries`
  ·`/dump.sql`)는 정의상 화이트리스트 밖이라 이제 전부 404 다. 당일 추가하는 커스텀 룰은 같은
  regex set 을 `and_statement` 한쪽 항으로 넣어야 이 성질이 유지된다.
- **경로 목록 근거**: 앱 바이너리 3종에 `/v1/…` 문자열이 각 1개뿐이고 path parameter 가 없다
  (`/v1/product/{id}` 형태 없음, 전부 쿼리스트링 선택). 화이트리스트는 Ingress 라우팅 3개 +
  `/images/*` 로 닫힌다. `/healthcheck` 는 제외 — Ingress 규칙이 없어 정상 요청도 CloudFront 경유
  404 라, 넣으면 "정상 404 / 비정상 403" 불일치가 생긴다.
- **text transformation**: `URL_DECODE` + `NORMALIZE_PATH`. `LOWERCASE` 는 뺐다 — ALB path-pattern 과
  CloudFront path pattern 이 둘 다 대소문자 구분이라 `/V1/USER` 는 어차피 404 다. 소문자화하면
  정상 `/V1/USER` 는 404 인데 비정상만 403 이 되어 두 계층이 어긋난다.
  ALB 문서: "A path pattern is case-sensitive" / "The rule evaluation is performed only after URI
  normalization occurs" — 후자가 `NORMALIZE_PATH` 를 넣은 근거다. ALB 도 정규화 후 평가하므로
  `/v1/user/../../etc/passwd` 를 양쪽이 똑같이 `/etc/passwd` 로 보고 404 로 수렴한다.
  https://docs.aws.amazon.com/elasticloadbalancing/latest/application/rule-condition-types.html
  (같은 문서에서 `http-header`·`query-string` 은 대소문자 무시, `http-request-method` 는 구분)
- **당일 바꿀 것**: 앱·경로가 바뀌면 `terraform.tfvars` 의 `waf_api_path_regexes` 만 교체한다.

### 2026-08-16 — `waf/` 콘솔용 조각 6개 삭제, UA 룰만 terraform 으로 이관

- **상태**: `waf/{denied-paths,denied-querystring,denied-ua}.regx` 와 `block-*.json` 은 저장소 어디서도
  참조되지 않는 연습 세션 잔여물이었다. 패턴이 플레이스홀더(`^/(block|할|목록)(/|$)`, `(block|할|ua)`)고
  JSON 의 regex set ARN 에 연습 계정 ID(`346151107821`)와 `<id>` 자리표시자가 박혀 있어 그대로는 못 쓴다.
- **경로 차단(`denied-paths`) 폐기**: scope-down 도입으로 **자기모순**이 됐다. 화이트리스트 밖 경로는
  애초에 룰에 닿지 않고, 굳이 닿게 만들면 404 여야 할 응답이 403 으로 나간다. 스캔 경로
  (`/.svn/entries`·`/dump.sql`)는 이제 전부 404 로 떨어지는 게 정답이다.
- **쿼리스트링 차단(`denied-querystring`) 폐기**: 관리형 SQLiRuleSet·KnownBadInputsRuleSet 과 중복이고,
  위 오탐 사고(커스텀 SQLi 룰이 정상 24,220건 차단)가 정확히 이 계열이다. 관리형으로 갈음한다.
- **UA 차단만 존치**: UA 는 판별력이 '강' 이고 부하 생성기(브라우저형 Chrome UA)와 교집합이 0 이라
  유일하게 값이 있다. `waf.tf` 의 `scanner-ua` 룰로 이관하면서 **`and_statement` 로 경로 화이트리스트를
  같이 걸었다** — 관리형 룰의 `scope_down_statement` 와 동등한 조건이다. 이게 빠지면 스캐너가 없는 경로를
  긁을 때 404 대신 403 이 나가 과제지 요구와 어긋난다.
- **UA 패턴은 소문자로 두고 `LOWERCASE` 변환으로 맞춘다** — WAF 정규식에 `(?i)` 인라인 플래그를
  쓰지 않기 위해서다. `COMPRESS_WHITE_SPACE` 는 기존 콘솔 조각의 설정을 그대로 가져왔다.
- **UA 목록을 terraform 변수로 두는 안 기각**: 처음엔 `waf_scanner_ua_regexes` tfvars 변수로 넣고
  `count` 로 룰을 껐다 켰다 하게 짰다가 되물렸다. UA 는 **트래픽 로그를 보고 실시간으로 정하는 값**인데
  apply 는 본 PC 전용이라(CLAUDE.md), 로그 분석(CloudShell) → 본 PC → tfvars → apply 왕복이 생긴다.
  트래픽이 이미 들어오는 중에 이 왕복을 도는 건 설계가 잘못된 것이다.
- **채택**: terraform 은 **regex pattern set 두 개만** 만든다. `scanner-ua` 룰 자체는 `waf/scanner-ua.json`
  으로 빼서 당일 콘솔 JSON editor 로 넣는다. 룰을 terraform 에 두면 (a) 켜고 끌 때 apply 왕복이 생기고
  (b) 검증 못 한 `and_statement`+ARN 참조 HCL 이 apply 를 통째로 막을 수 있다 — 배포 경로에
  미검증 코드를 두지 않는다. 세트는 단순 리소스라 그 위험이 없다.
- **`__disabled__scanner__ua__` 자리표시자**: `regular_expression` 0개를 terraform 스키마는 허용하나
  WAFv2 API 가 빈 목록을 받는지 문서에 없다. 룰이 빠진 지금은 세트가 참조되지도 않지만,
  세트 생성 자체가 실패하면 당일 손댈 게 늘어나므로 그대로 둔다.
- **콘솔 편집 시 리전 선택기를 Global (CloudFront)** 로 — us-east-1 리전 스코프와 목록이 다르다.
  `lifecycle { ignore_changes = [regular_expression] }` 이 없으면 다음 apply 가 이걸 되돌린다 —
  이 한 줄이 설계의 핵심이다.
- **자리표시자를 남기는 이유**: `regular_expression` 블록 0개를 terraform 스키마는 허용하지만
  (provider schema 확인: nesting_mode set, min_items 없음) WAFv2 API 가 빈 `RegularExpressionList` 를
  받는지는 문서에 없다. 대회 중에 확인할 일이 아니라 `__disabled__scanner__ua__`(어떤 UA 와도 불일치)
  하나를 남긴다. 콘솔에서 봐도 꺼진 상태임이 드러난다.
- **`api_paths` 는 terraform 에 그대로 둔다**: 경로 화이트리스트는 Ingress 라우팅과 한 몸이라
  바뀔 때 매니페스트도 같이 바뀌는 **배포 시점 값**이고, 403/404 를 가르는 정확성 핵심이라 코드에
  남겨 리뷰 대상으로 둔다. 실시간 튜닝 축이 아니다 — 두 세트의 수명주기가 다르다.
- **당일 절차**: README STEP 12 "스캐너 UA 차단 켜기". 부하 생성기 UA 가 브라우저형인지 먼저 확인하고
  도구형이면 켜지 않는다 — 채점 트래픽을 직접 죽인다. 되돌리기는 자리표시자 하나로 다시 덮어쓰기.

### 2026-08-10 — teardown 이 스크립트 잔여물을 안 지워 `Karpenter-skills-eks` 가 DELETE_FAILED

- **문제**: STEP 99(Ingress → 클러스터 → terraform)가 `scripts/karpenter.sh`·`scripts/lbc.sh` 가 만든 걸
  하나도 안 지웠다. 계정에 `Karpenter-skills-eks` 스택이 `DELETE_FAILED` 로 남았고, 실패 이벤트는 정책 6개
  전부 `Cannot delete a policy attached to entities. (Service: Iam, Status Code: 409)` 였다.
- **원인 ①**: 정책 6개(`KarpenterController*Policy-skills-eks`)는 CFN 소유인데, 그걸 붙인 역할
  `KarpenterControllerRole-skills-eks` 는 `karpenter.sh` 가 `aws iam create-role` 로 **스택 밖에** 만든다.
  CFN 은 자기가 안 만든 역할을 안 지우므로 역할이 정책을 붙든 채 남아 정책 삭제가 전부 409 다.
  `AWSLoadBalancerControllerRole-skills-eks` 도 같은 구조로 고아가 된다.
- **원인 ②**: `00-nodeclass.yaml` 이 `role` 만 지정하므로 인스턴스 프로파일 `skills-eks_<hash>` 는
  **Karpenter 가 런타임에** 만든다 — CFN·terraform·eksctl 어디에도 없다. ①만 고치면 이번엔 프로파일이
  `KarpenterNodeRole` 삭제를 막아 스택이 또 DELETE_FAILED 로 떨어진다. EC2NodeClass 삭제 시 finalizer 로
  정리되는 것으로 보이나 [nodeclasses 문서](https://karpenter.sh/docs/concepts/nodeclasses/)에 lifecycle
  명시가 없어 **teardown 에서 명시적으로 지운다**(있으면 지우고 없으면 넘어간다).
- **채택**: `scripts/teardown.sh` 하나로 프로파일 → 컨트롤러 역할 2개 → 스택 순으로 되돌린다. 정상 teardown 과
  이미 DELETE_FAILED 인 스택 복구가 같은 명령이라 복구용 분기를 두지 않았다. STEP 99 에는 NodePool·NodeClass
  삭제 단계를 클러스터 삭제 앞에 넣었다 — Karpenter 가 살아 있어야 자기가 띄운 EC2 를 회수한다.
- **지우지 않는 것**: `AWSLoadBalancerControllerIAMPolicy`. 이름에 클러스터명이 없어 다른 세트와 공유하고
  (실측 AttachmentCount 3), `lbc.sh` 는 이미 있으면 그냥 넘어간다. 역할에서 detach 만 한다.
- **기각**: `delete-stack --retain-resources` 로 정책 6개를 남기고 스택만 지우는 안 — 이름이 고정이라
  다음 배포에서 `aws cloudformation deploy` 가 AlreadyExists 로 깨진다. 콘솔 수동 삭제 — 재현이 안 된다.
- **검증**: 실행 후 스택 부재, `skills-eks` 이름의 IAM 역할·정책·인스턴스 프로파일·SQS 큐 전부 없음.

### 2026-08-09 — `amazon-cloudwatch-observability` addon 재도입 (사용자 방침)

- **문제**: 3과제는 "앱을 로그·메트릭으로 운영"하는 과제(`task-sample.md:145`)인데 앱 로그
  파이프라인이 없었다. `4b6e55c`에서 addon을 걷어낸 뒤 앱 stdout은 `kubectl logs`뿐이라
  로그 분석·장애 감지 항목에 보여줄 게 없다.
- **채택**: 두 버전으로 나눈다. **일반 버전**은 `eksctl/cluster.yaml`의 addon 블록(기본값 그대로,
  클러스터 생성에 포함 → 런북 명령 무변경), **최적화 버전**은 `eksctl/cloudwatch-tuned.yaml`을
  `eksctl update addon -f eksctl/cloudwatch-tuned.yaml` 한 줄로 덧씌운다. 되돌릴 때는
  `cluster.yaml`의 일반 버전 블록을 같은 명령으로 다시 적용한다. **버전을 나누는 이유는 당일
  바이너리가 계측된 버전일 수 있어서다** — 그때는 일반 버전(Application Signals·X-Ray 포함)이
  그대로 답이고, 계측이 없다고 확인되면 최적화 버전으로 수집 범위만 줄인다.
- **채택**: IAM은 Pod Identity(`podIdentityAssociations`, SA `cloudwatch-agent`).
  `aws eks describe-addon-configuration ... --query podIdentityConfiguration`은
  `CloudWatchAgentServerPolicy` 하나만 권장하지만, **공식 문서가 이 addon에 요구하는 두 정책
  (`CloudWatchAgentServerPolicy` + `AWSXrayWriteOnlyAccess`)을 두 파일 모두에 붙인다.**
  X-Ray를 빼면 당일 계측 바이너리가 나왔을 때 IAM부터 되돌려야 하고, Application Signals를
  다시 켜는 것만으로 끝나지 않는다. 최적화 버전에서도 정책은 그대로 두고 수집 범위만 줄인다.
  `iam.withOIDC` 없는 현재 구조를 그대로 두고 저장소의 Pod Identity 통일도 유지된다.
  IRSA로 바꿀 이유가 없다(채점이 annotation을 읽지 않는다).
- **최적화 버전이 기본값에서 벗어난 두 곳** (`configurationValues`):
  ① `applicationSignals.enabled: false` — **현재 제공 바이너리 기준**으로 Go라 자동 계측 대상
  언어(Java·Python·Node·.NET)가 아니어서 webhook과 트레이스 파이프라인만 돈다. 당일 바이너리가
  바뀌면 이 파일을 쓰지 않는다(일반 버전 유지).
  ② 컨테이너 로그를 `default` ns만 수집 — 기본 `application-log.conf`의 INPUT `Path`가
  `/var/log/containers/*.log` 전체다. `*_default_*.log`로 좁히고, 무의미해진 `Exclude_Path`와
  fluent-bit·cloudwatch-agent 자기 로그 INPUT 2개를 뺐다. 원본은 `aws-observability/helm-charts`
  의 `charts/amazon-cloudwatch-observability/values.yaml`.
- **CPU/메모리 requests는 기본값 유지**. 부하 중 agent가 스로틀되면 로그·메트릭이 끊기는데,
  그건 채점 축(로그 기반 운영)을 직접 깎는다. 줄이려면 수집 범위를 줄이는 쪽이 맞다.
- **감수하는 것 (a)**: DaemonSet 2개가 **모든 노드**에서 300m/153Mi를 먼저 뗀다(operator는
  시스템 노드에 100m 추가). t3.medium allocatable ~1930m 기준 여유가 730m → 330m로 줄고,
  Karpenter 노드도 노드당 앱 파드를 하나 덜 받는다 → 비용 ratio에 불리. 용량 검산표는
  `ARCHITECTURE.md`에 갱신했다. `kubeStateMetrics`·`nodeExporter`는 차트 주석상
  `otelContainerInsights.enabled`(기본 false)일 때만 생성되므로 안 뜬다.
- **감수하는 것 (b)**: 아래 Bottlerocket 결정의 "k8s에 hostPath·DaemonSet·privileged가 전혀
  없다"는 전제가 깨진다. 배포 후 `kubectl -n amazon-cloudwatch get pods`로 두 DaemonSet이
  Bottlerocket 노드에서 Running인지, application 로그 그룹에 실제로 들어오는지 확인할 것.
- **함정(실측) ①**: addon의 `podIdentityAssociations`도 `namespace`가 필수다. 공식 문서 예제는
  `serviceAccountName`만 보여주는데 그대로 쓰면 eksctl이
  `podIdentityAssociations[0].namespace must be set`으로 막는다(eksctl 0.229.0, `--dry-run`).
- **함정 ②**: `update addon`에서 `podIdentityAssociations`는 상태의 단일 소스라, 최적화 파일에서
  빼면 검증 에러가 난다(빈 목록으로 두면 연결이 지워진다). 그래서 두 파일에 같은 블록이 중복된다.
  `resolveConflicts: overwrite`도 필요하다 — 기존 configMap과 충돌한다.
- **검증**: 두 파일의 `configurationValues`를 `describe-addon-configuration`의
  `configurationSchema`(`additionalProperties: false`)에 jsonschema로 통과시켰고,
  `eksctl create cluster --dry-run`과 `eksctl get addon -f cloudwatch-tuned.yaml`(설정 파일
  파싱·검증 통과 후 클러스터 부재로 404)이 정상이다. 실제 수집 확인은 배포 후 몫.

### 2026-08-09 — 본 PC를 terraform·eksctl로 축소, Karpenter·LBC를 스크립트로 분리 (사용자 방침)

- **문제**: 본 PC가 terraform·eksctl·helm·kubectl·aws를 전부 돌렸다. 대회 PC는 재시동 시 초기화되고
  AI 보조도 없어, 설치·PATH를 맞춰야 할 도구가 늘수록 실패 지점이 는다. 동시에 `eksctl/cluster.yaml`이
  Karpenter 통합과 LBC IAM까지 떠안아 eksctl 버전 변화에 클러스터 생성 자체가 노출돼 있었다.
- **채택**: 본 PC = terraform + eksctl. helm·kubectl은 리전 CloudShell로 옮기고, Karpenter·LBC는
  공식 문서를 그대로 옮긴 `scripts/karpenter.sh`·`scripts/lbc.sh`로 뺐다. eksctl에는 클러스터·서브넷·
  MNG 1대·addon 2개·`product` SA만 남는다.
- **파생 효과**: Karpenter가 빠지면서 `iam.withOIDC: true`가 필요 없어졌다. 저장소에서 IRSA가 완전히
  사라지고 모든 SA가 Pod Identity로 통일된다. Karpenter 공식 getting-started가 Pod Identity 경로를
  제공하므로 "공식 문서를 따른다"는 조건과 충돌하지 않는다.
- **공식 명령에서 벗어난 세 곳** (스크립트 주석에 근거를 남겼다):
  ① `replicas=1`/`replicaCount=1` — 차트 기본 2는 두 번째 replica가 Pending이 되어 Karpenter가
  자기 자신을 위한 노드를 띄운다. 유휴 EC2 1대가 비용 ratio 12점의 전제다.
  ② Karpenter 컨트롤러 requests 미지정 — 공식 helm 명령의 `cpu=1/memory=1Gi`는 t3.medium
  allocatable(~1930m)의 절반이라 앱 3종이 들어갈 자리가 없다. 차트 기본값은 `{}`이므로 플래그만 뺀다.
  ③ 노드 역할 인가를 `eksctl create iamidentitymapping`(aws-auth) 대신 `aws eks create-access-entry
  --type EC2_LINUX` — CloudShell에 eksctl을 두지 않기 위해서다. `--type EC2`는 Auto Mode 전용이라
  self-managed EC2 노드에는 `EC2_LINUX`가 맞다.
- **기각**: Karpenter를 걷어내고 MNG만으로 스케일 — MNG는 자체 오토스케일러가 없어 부하 구간에
  노드가 안 늘고, 그러면 비용 ratio가 하한 0.50을 밑돌아 12점이 통째로 0이 된다.
- **기각**: 이전 방식대로 eksctl `wellKnownPolicies.awsLoadBalancerController: true` 유지 —
  LBC IAM만 eksctl에 남기면 "eksctl 최소" 방침이 반쪽이 되고, 정책 JSON 두 단계를 아끼는 이득은
  스크립트가 대신 하면 사라진다.

### 2026-08-09 — 실행 환경 3분할과 파일 전달 (사용자 방침)

- **채택**: 본 PC(terraform·eksctl) / VPC CloudShell(이미지 빌드·DB 초기화) / 리전 CloudShell(k8s 전부).
  RDS가 private subnet이고 SG가 VPC CIDR만 허용해 DB 초기화는 VPC 환경에서만 된다. 반대로 k8s 채점이
  일반 CloudShell에서 도므로 kubectl 작업은 리전 환경에 둬 채점 경로를 계속 검증한다.
- **VPC CloudShell 제약(공식 문서)**: Actions Upload/Download 불가, 홈 비영구, IAM 사용자당 2개,
  인터넷은 private subnet + NAT일 때만. 이 중 업로드 불가가 설계를 결정했다.
- **채택**: 텍스트(매니페스트·스크립트·SQL·dump)는 전부 heredoc 복사·붙여넣기. 붙여넣을 수 없는
  제공 바이너리 3개만 S3 콘솔 수동 업로드 → `aws s3 cp`, push 후 `aws s3 rm`으로 지운다
  (버킷이 `/images/*`로 노출되므로).
- **기각**: S3를 상설 릴레이로 쓰기 — 릴레이는 또 하나의 동기화 대상이 되어, 당일 파일을 고칠 때마다
  어느 쪽이 최신인지 따져야 한다. `k8s/rendered/` 렌더링 단계도 같은 이유로 삭제하고 파일을 직접 편집한다.
- **기각**: DB 초기화를 리전 CloudShell + mysql 파드 + `kubectl cp`로 — 클러스터가 떠야 시작할 수
  있어 DB 초기화가 STEP 2 뒤로 밀린다. dump 적재가 임계경로라 앞당기는 쪽이 맞다.

### 2026-08-09 — 이름을 prefix 하나에서 파생 (사용자 방침)

- **문제**: `skills-vpc`·`skills-igw`는 접두사가 있는데 `s3-vpce`·`public-rtb`·`private-subnet-1`은
  없었고, DB 계열은 SG가 `skills-db`, 서브넷 그룹이 `skills-db-subnet`, IAM 역할과 프록시가 둘 다
  `skills-db-proxy`로 겹쳤다.
- **채택**: `variable "prefix"`(default `skills`) → `locals.tf`가 모든 이름을 파생. `terraform.tfvars`
  한 줄로 전부 바뀌고, 개별 이름만 과제지가 지정하면 해당 local 한 줄을 리터럴로 덮어쓴다.
  DB 계열 토큰은 `db`로 통일(`-db-sg`·`-db-subnet-group`·`-db-credentials`·`-db-proxy`·`-db-proxy-role`).
- **예외 둘**: DB identifier는 과제지 명시·정확일치 채점이라 `var.db_identifier`, S3 버킷은 전역 유일
  제약이라 `var.bucket_name`.
- **기각**: 파생식을 각 리소스 파일에 인라인으로 두기 — 이름을 고칠 지점이 여러 파일로 흩어진다.
  `locals.tf` 한 곳에 모아 두면 당일 검색 없이 바로 고친다.

### 2026-08-09 — proxy secret이 빈 채로 생성되는 함정 (targeted apply의 그래프 리프 절단)

- **문제(실측)**: STEP 1b `apply -target=aws_db_proxy_target.this` 후 `skills-db-credentials`의
  내용이 비어 프록시가 DB 인증에 실패했다. `-target`은 의존성 조상만 끌고 오는데
  `aws_secretsmanager_secret_version.db`는 아무도 참조하지 않는 그래프 리프라 plan에서 잘린다 —
  secret 리소스(조상)는 생기고 version(내용)만 빠진다. `outputs.tf`의 `db_password` output이
  이미 겪고 `depends_on`으로 가드한 함정과 같은 부류인데 secret version은 누락돼 있었다.
- **채택**: `aws_db_proxy.this`에 `depends_on = [aws_secretsmanager_secret_version.db]` 한 간선.
  targeted plan에 version이 포함되고, full apply에서도 version 생성 후 proxy가 뜨는 순서가 보장된다.
  런북에는 1b 직후 `aws secretsmanager describe-secret --query VersionIdsToStages` 검증을 추가했다.
- **기각**: version을 proxy `auth.secret_arn`에서 직접 참조하도록 바꾸기 — `secret_arn`은 version이
  아니라 secret ARN을 받는 필드라 의미가 왜곡된다. depends_on이 의도를 그대로 말한다.

### 2026-08-09 — proxy role policy도 같은 함정에 걸림 (위 항목의 일반화)

- **문제(실측)**: 위 수정 뒤에도 앱이 `db error: ping: Error 1045 (28000): Access denied for user
  'admin'@'10.0.2.195' (using password: YES)`로 죽고 프록시 대상이 UNAVAILABLE이었다. 계정 실물은
  `describe-db-proxy-targets` → `AUTH_FAILURE / "Proxy does not have any registered credentials"`,
  `list-role-policies --role-name skills-db-proxy-role` → `[]`. 즉 `aws_iam_role_policy.proxy_secret`이
  계정에 아예 없었다. `-target`은 **조상만** 끌어오는데 role policy는 `aws_iam_role.proxy`의
  **자손**이라 proxy_target의 조상이 아니다 — role(조상)은 생기고 권한만 빠진다. 위 항목을
  "리프"로만 좁게 이해해서 자손 쪽을 놓쳤다.
- **일반 규칙**: targeted apply에서 대상이 *동작하는 데* 필요하지만 조상이 아닌 리소스는 전부
  `depends_on`으로 고정한다. 자손 policy·attachment·association, 아무도 참조하지 않는 leaf가 해당된다.
  나머지를 훑은 결과 추가 대상은 없다 — `aws_s3_bucket_policy.cdn_read`와
  `aws_wafv2_web_acl_logging_configuration.this`는 STEP 9 전체 apply에서 생성되고,
  라우트 테이블 association은 STEP 1a가 명시적으로 target에 넣는다.
- **채택**: `aws_db_proxy.this`의 `depends_on`에 `aws_iam_role_policy.proxy_secret` 추가.
- **런북 교체**: 1b 검증을 `describe-secret`에서 `describe-db-proxy-targets`의 `TargetHealth`로 바꿨다.
  전자는 이 장애를 **통과시켰다** — secret version은 멀쩡했기 때문이다. TargetHealth 하나가
  시크릿 내용·IAM 권한·네트워크·비밀번호 일치를 한꺼번에 증명한다. 검증은 구성요소가 아니라
  최종 성공 조건을 봐야 한다.
- **기각**: 시크릿 JSON에 `engine`/`host`/`port`/`dbname`을 넣어 "RDS 타입 시크릿"으로 만들기 —
  콘솔의 시크릿 타입 라벨은 JSON 키로 추론하는 UI 분류일 뿐 서버측 필드가 아니고, RDS Proxy는
  `username`/`password`만 읽는다(AWS CLI 문서 경로가 정확히 그 두 키만 쓴다). 이번 장애와 무관하다.
- **기각**: 프록시 정책에 `kms:Decrypt` 추가 — 시크릿이 기본 관리형 키(`KmsKeyId: null`)를 쓰고
  그 키 정책이 계정 주체에 직접 허용한다. CMK로 바꿀 때만 필요하다.

### 2026-08-09 — STEP 1 apply를 1a/1b로 분리 (문서만)

- **문제**: STEP 1이 `-target=aws_db_proxy_target.this`까지 한 덩어리라 RDS Multi-AZ 때문에 15분
  블로킹되는데, 런북은 그 사이 새 창에서 STEP 2를 띄우라 지시했다. STEP 2 첫 줄이
  `terraform output -json private_subnet_ids`라 **진행 중인 apply의 state를 읽는다.** output 노드가
  아직 기록되기 전이면 `Output not found`. 당일 20분 임계경로에서 겪을 실패다.
- **채택**: targeted apply를 1a(네트워크·ECR·S3, ~3분) / 1b(RDS·Proxy, ~15분)로 분리. 1a 완료 +
  output 성공이 eksctl 시작 신호. `README.md`·`README.linux.md`·`ARCHITECTURE.md`만 변경, terraform
  코드는 무변경.
- **유지되는 것**: RDS ∥ EKS 병렬(1b와 STEP 2가 각자 창에서 동시), 총 소요(3분은 원래 apply의 앞부분),
  STEP 3~11 번호. terraform apply가 항상 하나만 도므로 state 락 충돌도 없다.
- **기각**: EKS를 terraform으로 흡수해 한 번의 apply로 RDS∥EKS를 자동 병렬화. eksctl의 addon·access
  entry·`podIdentityAssociations`·karpenter 통합을 전부 수작업 재작성해야 해 4시간 예산 밖이다.
- **기각**: 1a target 목록을 서브넷만으로 더 줄이기. NAT가 없으면 private 노드가 EKS API·ECR에 못
  붙어 어차피 STEP 2가 실패한다. NAT 생성 시간이 1a 3분의 대부분이다.

### 2026-08-09 — 노드 AMI를 Bottlerocket으로 (사용자 방침)

- **채택**: 노드가 뜨는 경로가 둘이라 두 곳을 같이 바꿨다 — `eksctl/cluster.yaml` MNG에
  `amiFamily: Bottlerocket` 추가, `k8s/00-nodeclass.yaml`의 `alias: al2023@latest` →
  `bottlerocket@latest`. 이전에는 MNG가 amiFamily 미지정(=eksctl 기본 AL2023)이라 NodeClass와
  우연히 일치했을 뿐 아무것도 고정돼 있지 않았다. 한쪽만 바꾸면 OS가 갈린다.
- **영향 없음 확인**: `k8s/`에 hostPath·DaemonSet·privileged·hostNetwork가 전혀 없고 앱 로그는
  stdout → `kubectl logs`뿐이라 노드 OS 의존이 0이다. 런북 명령도 무변경(README 손대지 않음).
- **감수하는 것**: Bottlerocket에는 SSH·셸이 없고 SSM 에이전트도 MNG 기본 정책에 없다. 노드에
  직접 붙을 수단이 사라지지만 런북이 노드 셸을 쓰지 않으므로 실사용 손실은 없다. 정말 필요하면
  `kubectl debug node/<name>`.
- **롤백 조건**: `aws ssm get-parameter --name /aws/service/bottlerocket/aws-k8s-1.36/x86_64/latest/image_id`
  가 실패하면 그 k8s 버전용 Bottlerocket AMI가 아직 없다는 뜻이다. 위 2곳을 AL2023으로 되돌린다.
- **기각**: `blockDeviceMappings` 직접 지정. alias를 쓰면 Karpenter가 Bottlerocket용 기본값
  (OS 볼륨 + 데이터 볼륨 2개)을 알아서 붙인다.

### 2026-08-09 — IAM은 Pod Identity, LB는 internet-facing 단일 (사용자 방침)

- **채택**: AWS Load Balancer Controller SA를 IRSA(`iam.serviceAccounts`) → Pod Identity
  (`iam.podIdentityAssociations`)로 이동. eksctl의 `podIdentityAssociations`가 `wellKnownPolicies`를
  지원해 `awsLoadBalancerController: true` 편의 기능을 그대로 들고 갔다 — `iam_policy.json` 다운로드 +
  `aws iam create-policy` 2단계는 여전히 불필요하다. `eks-pod-identity-agent` addon은 이미 있었다.
  Helm 명령은 무변경(`serviceAccount.create=false`). 이제 우리가 만드는 SA는 전부 Pod Identity다.
- **유지(기각한 대안)**: `iam.withOIDC: true` 제거. eksctl karpenter 통합의 하드 요구사항이다
  ("OIDC must be defined in order to install Karpenter"). 지우려면 Karpenter를 IAM 역할·인스턴스
  프로파일·노드롤 access entry·Helm 설치까지 수동으로 깔아야 해서 4시간 예산에 맞지 않는다.
  Karpenter 컨트롤러 SA 한 곳만 IRSA로 남는다.
- **삭제**: private subnet의 `kubernetes.io/role/internal-elb` 태그(`terraform/vpc.tf`).
  internet-facing 단일 방침에서 쓰이지 않는다. internet-facing ALB의 서브넷 auto-discovery는
  퍼블릭 서브넷의 `kubernetes.io/role/elb`가 담당하므로 무관하다.
- **확인**: task-3는 CloudFront VPC Origin을 쓰지 않는다(`terraform/cloudfront.tf`는
  `custom_origin_config`). VPC Origin은 private subnet 리소스만 지원하므로 internal ALB를 강제하는데,
  여기엔 애초에 그 요구가 없다. 1·2과제 세트 셋(`set-05/task-1`, `set-05/task-2` module-2,
  `set-07/task-1`)은 반대로 mark가 `internal`을 정확일치로 검사하므로 같은 방침을 적용하지 않았다.

## 문서 근거

- eksctl `amiFamily: Bottlerocket` (managed node group):
  https://docs.aws.amazon.com/eks/latest/userguide/launch-node-bottlerocket.html
- Bottlerocket에 SSH·셸 없음(admin container 필요):
  https://github.com/bottlerocket-os/bottlerocket#admin-container
- Karpenter EC2NodeClass AMI alias(`bottlerocket@latest`)와 계열별 기본 blockDeviceMappings:
  https://karpenter.sh/docs/concepts/nodeclasses/
- eksctl Pod Identity Associations 스키마(`wellKnownPolicies` 지원):
  https://docs.aws.amazon.com/eks/latest/eksctl/pod-identity-associations.html
- Karpenter 설치 (CloudFormation + Pod Identity + Helm):
  https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
- Karpenter 를 기존 클러스터에 추가 (노드 역할 인가·discovery 태깅):
  https://karpenter.sh/docs/getting-started/migrating-from-cas/
- EKS access entry type (`EC2` 는 Auto Mode 전용, self-managed EC2 는 `EC2_LINUX`):
  https://docs.aws.amazon.com/eks/latest/APIReference/API_CreateAccessEntry.html
- WAF → CloudWatch Logs 로그 그룹 요건 (`aws-waf-logs-` prefix, 같은 리전, resource policy 자동 생성):
  https://docs.aws.amazon.com/waf/latest/developerguide/logging-cw-logs.html
- CloudShell VPC 환경 제약 (Actions 업로드 불가·비영구 홈·NAT 필요·최대 2개):
  https://docs.aws.amazon.com/cloudshell/latest/userguide/using-cshell-in-vpc.html
- LBC 인증 옵션(IRSA / Pod Identity):
  https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
- CloudFront VPC Origin은 private subnet 리소스 전용:
  https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html
- WAF 로그 필드: https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html
- Logs Insights QL 문법: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html
- 저장 쿼리 파라미터 (`{{param}}`): https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_Insights-Saving-Queries.html
- WAF 로그의 CloudWatch 분석 패턴 (nested 필드·parse): https://aws.amazon.com/blogs/mt/analyzing-aws-waf-logs-in-amazon-cloudwatch-logs/
