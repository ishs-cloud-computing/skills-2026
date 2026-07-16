# DB 초기화 런북 (PowerShell)

메인 런북 [../README.md](../README.md) STEP 7에서 진입한다. **cwd = task-3/** 기준, 본 컴퓨터 PowerShell. Linux bash 판은 [README.linux.md](README.linux.md).

- 모든 작업은 **직결 엔드포인트**(`db_endpoint`)로 한다 — 프록시 경유 대량 적재는 세션이 프록시에 피닝되어 풀링을 깨뜨린다. 앱만 프록시(`db_proxy_endpoint`)를 쓴다.
- 정적 SQL은 이 디렉토리의 `.sql` 파일을 `Get-Content -Raw`로 stdin 주입, 비밀번호가 들어가는 문장(ALTER USER)만 문자열 — 시크릿을 git에 넣지 않기 위함.
- mysql 클라이언트는 클러스터 안에서 `kubectl run`으로 띄운다(로컬 mysql 불필요). 따라서 **STEP 5 노드풀이 Ready여야 한다** — 첫 `kubectl run`이 노드 생성을 트리거해 ~2분 걸린다.
- **순서 주의**: 1·2번(스키마·ALTER USER)은 즉시 끝나고 앱이 붙기 위한 전제조건이다. 3번 dump 적재(50만행)가 느린 쪽이므로 **2번이 끝나면 README STEP 8(앱 배포)을 새 창에서 시작**하고 3번을 이어서 돌린다.

## 0. 전제

```powershell
# ── Windows PowerShell ──
# README STEP 0에서 이미 수행: $env:DB_PASSWORD (terraform.tfvars의 db_password와 동일)
$DB_HOST = terraform -chdir=terraform output -raw db_endpoint
```

## 1. 스키마 (db/01-schema.sql — 과제지 SQL 그대로)

```powershell
# ── Windows PowerShell ──
Get-Content db/01-schema.sql -Raw | kubectl run db-init --rm -i --restart=Never `
  --image=public.ecr.aws/docker/library/mysql:8.0 -- `
  mysql -h $DB_HOST -uadmin "-p$($env:DB_PASSWORD)" dev
```

## 2. admin 유저 native 플러그인 전환 (앱 배포 전제조건)

프록시 클라이언트 인증이 MySQL Native(`client_password_auth_type = MYSQL_NATIVE_PASSWORD`,
terraform/rds-proxy.tf) → 백엔드 admin 유저도 native 플러그인이어야 한다
(MySQL 8.0 기본이 caching_sha2_password인 경우 대비, 이미 native면 무해).

**프록시가 백엔드에 인증하기 위한 하드 전제조건이라 dump 적재보다 앞에 온다** — 즉시 끝나는 문장을 50만행 뒤에 세울 이유가 없다. 이게 끝나면 앱이 붙을 수 있다.

```powershell
# ── Windows PowerShell ──
"ALTER USER 'admin'@'%' IDENTIFIED WITH mysql_native_password BY '$($env:DB_PASSWORD)';" |
  kubectl run db-authfix --rm -i --restart=Never `
  --image=public.ecr.aws/docker/library/mysql:8.0 -- `
  mysql -h $DB_HOST -uadmin "-p$($env:DB_PASSWORD)" dev
```

> 여기서 **README STEP 8(앱 배포)을 새 창에서 시작**한다. 스키마·인증이 끝났으므로 앱은 빈 테이블에 정상 연결되고, 데이터는 T+60 트래픽 전에만 있으면 된다. 노드 생성·이미지 pull·파드 기동·TG 등록·ALB 헬스체크가 아래 dump 적재와 겹쳐 ~2–3분 회수된다.

## 3. 제공 dump 적재 (느림 — STEP 8과 병행)

`load_user.dump`는 당일 제공 — 경로를 실제 위치로 바꾼다.

```powershell
# ── Windows PowerShell ──
Get-Content load_user.dump -Raw | kubectl run db-load --rm -i --restart=Never `
  --image=public.ecr.aws/docker/library/mysql:8.0 -- `
  mysql -h $DB_HOST -uadmin "-p$($env:DB_PASSWORD)" dev
```

느리면(`Get-Content -Raw`가 파일 전체를 메모리에 올리고 kubectl stdin은 빠른 파이프가 아니다) dump를 S3에 올리고 파드가 직접 당기는 방식으로 전환한다. 크기를 모르는 지금 미리 만들 이유는 없다.

## 4. email 인덱스 (db/02-index.sql — dump 적재 후 필수)

GET /v1/user?email= 이 유일한 조회 패턴인데 스키마에 email 인덱스가 없다(풀스캔 = 0.2s SLO 전멸).

```powershell
# ── Windows PowerShell ──
Get-Content db/02-index.sql -Raw | kubectl run db-index --rm -i --restart=Never `
  --image=public.ecr.aws/docker/library/mysql:8.0 -- `
  mysql -h $DB_HOST -uadmin "-p$($env:DB_PASSWORD)" dev
```

## 5. 검증

```powershell
# ── Windows PowerShell ──
@"
SELECT COUNT(*) FROM user;
SHOW INDEX FROM user;
SELECT user, plugin FROM mysql.user WHERE user='admin';
"@ | kubectl run db-verify --rm -i --restart=Never `
  --image=public.ecr.aws/docker/library/mysql:8.0 -- `
  mysql -h $DB_HOST -uadmin "-p$($env:DB_PASSWORD)" dev
```

기대값: user 행 수 = dump 건수(약 50만), `idx_email` 인덱스 존재, plugin = `mysql_native_password`.
