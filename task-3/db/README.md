# DB 초기화 런북 (RDS 콘솔 → CloudShell)

메인 런북 [../README.md](../README.md) STEP 7에서 진입한다. **전 과정을 브라우저 CloudShell에서** 수행하므로
로컬 OS와 무관하다 — bash 판 [README.linux.md](README.linux.md)와 내용이 동일하다.

- RDS **인스턴스** 콘솔에서 접속하므로 자동으로 **직결 엔드포인트**다(프록시 아님) — 대량 적재가 프록시에
  피닝돼 풀링을 깨는 문제를 피한다. 앱만 프록시(`db_proxy_endpoint`)를 쓴다.
- `.sql`·`.dump`는 전부 텍스트다 — 이 저장소의 파일 내용을 `vim`으로 붙여넣고 저장한 뒤,
  **버튼이 넣어준 접속 명령을 히스토리(↑)로 불러와 뒤에 `< 파일`만 붙여** 적재한다.
- **파드 대신 콘솔 셸을 쓰는 이유**: `kubectl run` 파드는 노드풀 Ready가 선행돼야 하고, 파드 안 파괴 명령은
  복구가 어렵다. RDS 콘솔 "Connect using CloudShell"은 VPC 네트워킹·엔드포인트·클라이언트를 한 번에 해결해
  DB 초기화를 EKS에서 분리한다. → **STEP 5(노드풀)와 무관하며, RDS가 생성된 STEP 3 apply 완료 후 언제든 실행 가능.**
- **순서 주의**: 1·2번(스키마·ALTER USER)은 즉시 끝나고 앱이 붙기 위한 전제조건이다. 3번 dump 적재가 느린
  쪽이므로 **2번이 끝나면 메인 STEP 8(앱 배포)을 시작**하고 3번을 이어서 돌린다.

## 0. RDS CloudShell 접속

RDS 콘솔 → DB `apdev-rds-instance` → **Connectivity & security** 탭 → **Connect using CloudShell** 클릭.
버튼이 접속 명령(엔드포인트·유저 포함)을 CloudShell에 **자동 입력**한다 → Enter → **password 입력**이면 접속 완료.
엔드포인트를 찾거나 mysql 클라이언트를 설치할 필요가 없다. 이 접속 명령은 이후 히스토리로 재사용한다.

```
mysql> 프롬프트 확인 → :exit 로 셸에 돌아오면 접속 명령이 히스토리에 남는다.
```

## 1. 스키마 (db/01-schema.sql — 과제지 SQL 그대로)

`vim 01-schema.sql`로 열어 `db/01-schema.sql` 내용을 붙여넣고 `:wq` 저장한 뒤,
히스토리(↑)의 **접속 명령 뒤에 `< 01-schema.sql`만 붙여** 실행한다(password 입력).

```bash
# ── CloudShell ── ↑ 접속 명령(엔드포인트 자동 포함) + 리다이렉트
<접속 명령> < 01-schema.sql
```

## 2. admin 유저 native 플러그인 전환 (앱 배포 전제조건)

프록시 클라이언트 인증이 MySQL Native(`client_password_auth_type = MYSQL_NATIVE_PASSWORD`,
terraform/rds-proxy.tf) → 백엔드 admin 유저도 native 플러그인이어야 한다
(MySQL 8.0 기본이 caching_sha2_password인 경우 대비, 이미 native면 무해).

**프록시가 백엔드에 인증하기 위한 하드 전제조건이라 dump 적재보다 앞에 온다.** 접속한 `mysql>` 프롬프트에서
그대로 실행한다 — 비밀번호가 문장에 들어가므로 파일 대신 프롬프트에 입력해 git에 남기지 않는다.

```sql
-- mysql> 프롬프트에서, <PASSWORD>를 terraform.tfvars의 db_password로
ALTER USER 'admin'@'%' IDENTIFIED WITH mysql_native_password BY '<PASSWORD>';
```

> 여기서 **메인 STEP 8(앱 배포)을 시작**한다. 스키마·인증이 끝났으므로 앱은 빈 테이블에 정상 연결되고,
> 데이터는 T+60 트래픽 전에만 있으면 된다. 노드 생성·이미지 pull·파드 기동·TG 등록·ALB 헬스체크가 아래
> dump 적재와 겹쳐 ~2–3분 회수된다.

## 3. 제공 dump 적재 (느림 — STEP 8과 병행)

`vim load_user.dump`로 열어 제공 dump 내용을 붙여넣고 `:wq` 저장한 뒤, 히스토리의 접속 명령을 재사용한다.

```bash
# ── CloudShell ── ↑ 접속 명령 + 리다이렉트
<접속 명령> < load_user.dump
```

당일 dump가 커서(예: ~50만행) 붙여넣기가 비현실적이면, dump를 S3에 올리고
`aws s3 cp s3://<bucket>/load_user.dump .`로 내려받아 같은 방식으로 적재한다(CloudShell은 pre-auth AWS CLI 보유).

## 4. email 인덱스 (db/02-index.sql — dump 적재 후 필수)

GET /v1/user?email= 이 유일한 조회 패턴인데 스키마에 email 인덱스가 없다(풀스캔 = 0.2s SLO 전멸).
dump가 DROP/CREATE TABLE을 포함할 수 있으므로 반드시 dump 뒤에 실행한다.

`vim 02-index.sql`로 열어 `db/02-index.sql` 내용을 붙여넣고 `:wq` 저장한 뒤:

```bash
# ── CloudShell ── ↑ 접속 명령 + 리다이렉트
<접속 명령> < 02-index.sql
```

## 5. 검증

접속한 `mysql>` 프롬프트에서:

```sql
SELECT COUNT(*) FROM user;
SHOW INDEX FROM user;
SELECT user, plugin FROM mysql.user WHERE user='admin';
```

기대값: user 행 수 = dump 건수, `idx_email` 인덱스 존재, plugin = `mysql_native_password`.
