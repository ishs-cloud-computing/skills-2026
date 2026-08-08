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

## 결정 로그

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
- eksctl Karpenter — `withOIDC: true` 필수:
  https://docs.aws.amazon.com/eks/latest/eksctl/eksctl-karpenter.html
- LBC 인증 옵션(IRSA / Pod Identity):
  https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
- CloudFront VPC Origin은 private subnet 리소스 전용:
  https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html
- WAF 로그 필드: https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html
- Logs Insights QL 문법: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html
- 저장 쿼리 파라미터 (`{{param}}`): https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_Insights-Saving-Queries.html
- WAF 로그의 CloudWatch 분석 패턴 (nested 필드·parse): https://aws.amazon.com/blogs/mt/analyzing-aws-waf-logs-in-amazon-cloudwatch-logs/
