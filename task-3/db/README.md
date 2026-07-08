# DB 초기화 런북

메인 런북 [../README.md](../README.md) 7번에서 진입한다. **cwd = task-3/** 기준.

- 모든 작업은 **직결 엔드포인트**(`db_endpoint`)로 한다 — 프록시 경유 대량 적재는 세션이 프록시에 피닝되어 풀링을 깨뜨린다. 앱만 프록시(`db_proxy_endpoint`)를 쓴다.
- 정적 SQL은 이 디렉토리의 `.sql` 파일, 비밀번호가 들어가는 문장(ALTER USER)만 echo 원라이너 — 시크릿을 git에 넣지 않기 위함.

## 0. 전제

```bash
# README 0번에서 이미 수행: export DB_PASSWORD='...' (terraform.tfvars의 db_password와 동일)
DB_HOST=$(terraform -chdir=terraform output -raw db_endpoint)
MYSQL="mysql -h $DB_HOST -uadmin -p$DB_PASSWORD dev"
```

## 1. 스키마 (db/01-schema.sql — 과제지 SQL 그대로)

```bash
kubectl run db-init --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/mysql:8.0 -- $MYSQL < db/01-schema.sql
```

## 2. 제공 dump 적재

`load_user.dump`는 당일 제공 — 경로를 실제 위치로 치환한다.

```bash
kubectl run db-load --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/mysql:8.0 -- $MYSQL < load_user.dump
```

## 3. email 인덱스 (db/02-index.sql — dump 적재 후 필수)

GET /v1/user?email= 이 유일한 조회 패턴인데 스키마에 email 인덱스가 없다(풀스캔 = 0.2s SLO 전멸).

```bash
kubectl run db-index --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/mysql:8.0 -- $MYSQL < db/02-index.sql
```

## 4. admin 유저 native 플러그인 전환

프록시 클라이언트 인증이 MySQL Native(`client_password_auth_type = MYSQL_NATIVE_PASSWORD`,
terraform/rds-proxy.tf) → 백엔드 admin 유저도 native 플러그인이어야 한다
(MySQL 8.0 기본이 caching_sha2_password인 경우 대비, 이미 native면 무해).

```bash
echo "ALTER USER 'admin'@'%' IDENTIFIED WITH mysql_native_password BY '$DB_PASSWORD';" | \
  kubectl run db-authfix --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/mysql:8.0 -- $MYSQL
```

## 5. 검증

```bash
echo "SELECT COUNT(*) FROM user;
SHOW INDEX FROM user;
SELECT user, plugin FROM mysql.user WHERE user='admin';" | \
  kubectl run db-verify --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/mysql:8.0 -- $MYSQL
```

기대값: user 행 수 = dump 건수(약 50만), `idx_email` 인덱스 존재, plugin = `mysql_native_password`.
