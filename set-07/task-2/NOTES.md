# set-07 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 4개 고정. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 채점 커버 | 미해결 |
|------|------|-----------|--------|
| 1 | nosql | 6/6 (mark1.sh 전 항목 통과) | 없음 |
| 2 | cdn-function | 6/6 (mark2.sh 전 항목 통과) | 없음 |
| 3 | eks-scaling | 0/? | 미착수 |
| 4 | container-logging | 0/? | 미착수 |

### module-1 채점 커버리지 (mark1.sh ↔ 구현)
<!-- [x] apply 후 mark1.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->
<!-- 2026-07-26 실채점 결과로 전 항목 확정 -->

- [x] 1-1-A reservation 테이블 — 실채점: 이름·PK/SK·Streams·PAY_PER_REQUEST·PITR ENABLED 전부 기대값 출력
- [x] 1-2-A GSI + audit 테이블 — 실채점: gsi-user-reservations(HASH user_id/RANGE reserved_at, ALL) + audit PK event_id 정확 일치
- [x] 1-3-A Lambda + ESM — 실채점: python3.13/30/reservation-table/Enabled 정확 일치
- [x] 1-4-A EC2 :8080 — 실채점: Public IP 조회 + healthcheck 200
- [x] 1-5-A 조건부 쓰기 — 실채점: 200/409/409/200, 본문 일치 (본문·코드 줄바꿈 분리는 jsonify trailing newline — 지급 app.py 고유 동작)
- [x] 1-6-A Streams·sparse·audit — 실채점: 1 / ["reserved",true] / 1 / 0(sparse 확인) / 2, 전부 기대값

#### module-1 함정 (실채점에서 발견)

- **log group 선존재 충돌**: 첫 apply가 `/aws/lambda/bigbae-nosql-reservation-audit` already exists로 실패 →
  `aws logs delete-log-group --log-group-name /aws/lambda/bigbae-nosql-reservation-audit --region ap-southeast-1` 후 재apply로 해결.
  대회 당일 재배포 시 같은 충돌 가능 — destroy 없이 재apply 하는 상황이면 이 명령을 먼저.

### module-2 채점 커버리지 (mark2.sh ↔ 구현)
<!-- [x] apply 후 mark2.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->
<!-- 2026-07-26 실채점 결과로 전 항목 확정 -->

- [x] 2-1-A S3 버킷 — 실채점: 버킷명·오브젝트 2개·PAB·정책 전부 true (정책 검사 2개 값이 기대 출력과 달리 두 줄로 나오나 부분 일치 항목이라 통과)
- [x] 2-2-A KVS + 함수 — 실채점: 키 3개 값·ReqFn/ResFn DEPLOYED cloudfront-js-2.0·KVS 연결 true, 정확 일치
- [x] 2-3-A Distribution — 실채점: whitelist x-sp-ab / 0 300 3600 / redirect-to-https / OAC·cache policy true / 함수 2개, 정확 일치
- [x] 2-4-A 쿠키 강제 — 실채점: cookie_a_b_body true true, no_setcookie true true, HTTP→HTTPS 30x true true
- [x] 2-5-A 무작위 할당·보존 — 실채점: 배정 a, 본문·Max-Age·Path·재방문 유지·Set-Cookie 부재 전부 true (viewer-request 가 세운 assigned 헤더가 viewer-response 에 보이는 것 실증됨)
- [x] 2-6-A KVS 동적 반영 — 실채점: weight 1.0→/version-b, 0.0→/version-a, 0.3 복원 확인

#### module-2 함정 (구현 중 발견)

- **js-2.0 은 함수 인자 안의 await 금지**: `parseFloat(await kvs.get('weight'))` 가
  `SyntaxError: await in arguments not supported` 로 실행 시에만 죽는다 — CreateFunction(apply)은 검증 없이 통과.
  증상은 전 요청 503 + `x-cache: FunctionThrottledError` (라벨만 보면 스로틀로 오인).
  진단은 `aws cloudfront test-function --stage LIVE` 가 정답 (FunctionErrorMessage 에 행 번호까지 나옴).
  규칙: await 는 항상 `const x = await …` 단독 문장으로.

- **JS 리터럴 치환 범위**: 함수 소스(`terraform/cloudfront/*.js`)는 정적 파일이라 변수 미적용.
  쿠키명 `x-sp-ab`·헤더명 `x-sp-ab-assigned`·KVS 키명(`weight`/`version_a`/`version_b`)·`Max-Age=86400` 이
  바뀌면 req-fn.js·res-fn.js 를 직접 수정해야 하고, 쿠키명은 `ab_cookie_name` 변수(cache policy)와 함께 바꿔야 한다.
- **mark2.sh 가 weight 를 out-of-band 로 변경**(2-6, 종료 시 0.3 복원): 채점 직후 terraform plan 을 돌리면
  KVS 키 drift 가 보일 수 있다. 복원까지 끝났으면 무시.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

- module-1 apply: ~2분 30초 (1차 실패 apply + 재apply 포함, log group 수동 삭제 시간 제외)
- module-2 apply: ~4분 (distribution 배포 대기가 대부분)
- module-3 apply:
- module-4 apply:
- 공통 병목: EC2 user-data pip 설치(~1-2분)가 healthcheck 가능 시점을 늦춘다

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

### 2026-07-26 [module-2] KVS 키는 keys_exclusive 단일 리소스로 관리
- 맥락: 채점 2-2 가 `list-keys` 결과를 정확 일치로 검사 — 여분 키가 하나라도 있으면 실점. terraform MCP 로 6.56 문서 확인
- 채택: `aws_cloudfrontkeyvaluestore_keys_exclusive` (키 3개 선언, 미선언 키 자동 제거 + KVS API 호출 최소화)
- 기각: `aws_cloudfrontkeyvaluestore_key` ×3 → 수동 추가된 여분 키를 못 지우고, 키당 개별 API 호출
- 대가: 이 리소스가 KVS 키 전체의 단독 소유자가 됨 — 수동 put-key 는 다음 apply 때 제거됨 (채점 2-6 은 스스로 0.3 복원하므로 무관)

### 2026-07-26 [module-2] "Pay-as-you-go 타입"은 no-op (기본값)
- 맥락: 과제지가 "Pay-as-you-go 타입" distribution 을 요구. aws-knowledge MCP 확인: flat-rate 플랜(2025-11 출시)은 콘솔 전용 opt-in 구독이고 Terraform/API/CFN 에 플랜 인자 자체가 없음
- 채택: 아무 설정 안 함 — Terraform 생성 distribution 은 구조적으로 PAYG. `price_class` 는 엣지 로케이션 범위 설정으로 플랜과 무관하므로 미설정(기본 PriceClass_All)
- 기각: `price_class` 등으로 "타입"을 표현 → 과금 모델과 무관한 인자
- 대가: 없음

### 2026-07-26 [module-2] Set-Cookie 는 response.cookies 객체로, 발급 여부는 assigned 헤더로 게이트
- 맥락: 채점 2-4 는 쿠키 재방문 시 Set-Cookie 부재를, 2-5 는 첫 방문 시 `Path=/; Max-Age=86400` 발급을 정확 검사. aws-knowledge MCP 확인: CloudFront Functions 이벤트에서 Set-Cookie 헤더는 `response.headers` 가 아니라 `response.cookies` 로만 다룸
- 채택: req-fn 은 신규 배정시에만 `x-sp-ab-assigned` 요청 헤더를 세우고, res-fn 은 그 헤더가 있을 때만 `response.cookies['x-sp-ab']` 설정 (과제지 명세 그대로)
- 기각: `response.headers['set-cookie']` 직접 설정 → 문서상 cookies 객체 밖의 Set-Cookie 는 이벤트에 반영 안 됨. res-fn 이 request.cookies 부재로 판단 → 배정 버전(a/b)을 알 수 없어 uri 재파싱 필요
- 대가: viewer-request 가 세운 헤더가 viewer-response 의 event.request 에 보인다는 명시 문서 없음(AWS 공식 A/B 패턴이라 실동작은 검증됨) — apply 후 런북 2단계 curl 로 실측

### 2026-07-26 [module-2] 함수 JS 는 정적 파일 (templatefile 미사용)
- 맥락: 30% 변동 규칙상 리터럴은 변수화 대상이지만, JS 안의 쿠키·헤더·KVS 키명까지 변수화하려면 templatefile 필요
- 채택: 정적 `cloudfront/*.js` + NOTES 함정 절에 치환 범위 기록
- 기각: `templatefile()` 로 JS 템플릿화 → `${}` 이스케이프 관리 비용이 리터럴 4종 직접 수정보다 큼
- 대가: 쿠키명 변경 시 변수(`ab_cookie_name`)와 JS 2개 파일을 같이 고쳐야 함

### 2026-07-26 [module-1] mark.md의 기대 출력이 원본 pdf와 다른 오류를 해결
- 맥락: 기존 mark.md 1-6-A 기대 출력이 불일치하다는 문제를 확인했지만, 이는 원본 pdf에서 변환 도중 오류가 발생해 마지막 출력이 2번 작성된것임을 확인
- 채택: 수동으로 mark.md의 기대 출력을 원본 pdf와 동일하게 수정
- 기각: X
- 대가: X

### 2026-07-26 [module-1] default VPC → 자체 VPC로 전환 (아래 default VPC 결정 번복)
- 맥락: 대회 당일 30% 변동으로 "VPC 이름/CIDR 지정"이 나오면 data source 기반 default VPC는 변수화 불가 — retrofit 시 리소스 5개 신규 + 서브넷 교체로 인스턴스 재생성 (사용자 지적)
- 채택: 자체 VPC + public 서브넷 + IGW + 라우팅 (이름·CIDR은 vpc_name/vpc_cidr/subnet_cidr 변수)
- 기각: default VPC 유지 → 30% 규칙(이름·CIDR 변수화)과 구조적으로 충돌. create_vpc 토글 변수 → 안 쓰는 분기(죽은 유연성)
- 대가: 리소스 +5 (전부 무료), apply +30초

### 2026-07-26 [module-1] GSI를 key_schema 블록으로 선언
- 맥락: AWS provider 6.x에서 GSI `hash_key`/`range_key` 인자가 deprecated (terraform MCP로 6.56 문서 확인)
- 채택: `global_secondary_index` 내 `key_schema` 블록 (HASH user_id / RANGE reserved_at)
- 기각: 기존 세트처럼 `hash_key`/`range_key` 인자 → deprecation 경고, 향후 major에서 제거 예정
- 대가: 없음 (동일 결과)

### 2026-07-26 [module-1] EC2는 default VPC에 배치
- 맥락: 과제지가 VPC를 요구하지 않고, 채점(1-4~1-6)은 Public IP :8080 접근만 검사
- 채택: `data.aws_vpc.default` + 첫 서브넷. 없으면 `aws ec2 create-default-vpc`로 복구(런북 0단계)
- 기각: 커스텀 VPC(+서브넷·IGW·라우팅 ~6리소스) → 채점 무관 리소스
- 대가: 로컬 계정에 default VPC가 없어서 plan이 한 번 실패, create-default-vpc로 해결 (~1분)

### 2026-07-26 [module-1] Lambda handler는 lambda.handler (지급 파일명 그대로)
- 맥락: 지급 `lambda.py` 무수정 사용 조건. 파일명이 python 예약어와 같음
- 채택: `archive_file` source_file로 원본 zip, handler `lambda.handler` — 런타임은 importlib 로드라 모듈명 lambda 무관
- 기각: archive_file `source` 블록으로 zip 내부 파일명을 index.py로 개명 → 불필요한 우회
- 대가: 없음

### 2026-07-26 [module-1] app.py는 user-data base64 임베드로 배포
- 맥락: module-1은 Dockerfile 미지급 = EC2 직접 실행 전제. app.py+requirements 합계 ~7KB로 user-data 16KB 한도 내
- 채택: set-05 module-2에서 검증된 base64 heredoc + systemd(Restart=always) 패턴 재사용
- 기각: S3 업로드 + 인스턴스에서 다운로드 → 버킷·GetObject IAM·순서 의존만 늘고 이득 없음
- 대가: app.py 내용 변경 시 인스턴스 재생성(user_data 변경) 필요
