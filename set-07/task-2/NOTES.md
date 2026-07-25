# set-07 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 4개 고정. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 채점 커버 | 미해결 |
|------|------|-----------|--------|
| 1 | nosql | 6/6 (mark1.sh 전 항목 통과) | 없음 |
| 2 | cdn-function | 0/? | 미착수 |
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
- **mark.md 1-6-A 기대 출력 불일치**: 기대 블록은 6줄(마지막 "2" 2회)인데 채점 스크립트는 5개만 출력한다(마지막 audit 재확인 명령 없음).
  기대 블록 마지막 "2"는 중복 기재로 판단. jq pretty-print(멀티라인 배열)·jsonify trailing newline 등 서식 차이도 값 기준으로 판정할 것.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

- module-1 apply: ~2분 30초 (1차 실패 apply + 재apply 포함, log group 수동 삭제 시간 제외)
- module-2 apply:
- module-3 apply:
- module-4 apply:
- 공통 병목: EC2 user-data pip 설치(~1-2분)가 healthcheck 가능 시점을 늦춘다

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

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
