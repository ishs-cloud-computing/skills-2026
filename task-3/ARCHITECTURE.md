# task-3 설계 근거

## 트래픽 경로

```
사용자 → CloudFront ─┬─ /images/*  → (strip "/images") → S3 (OAC, 캐싱)
        (WAF 403)    └─ 그 외 전부 → VPC Origin → 내부 ALB ─┬─ /v1/user    → tg-user
                                                            ├─ /v1/product → tg-product
                                                            ├─ /v1/stress  → tg-stress
                                                            └─ 기본액션    → 404
파드 ← TargetGroupBinding(Auto Mode 내장) ← 타깃그룹
user/product → RDS Proxy → RDS(Multi-AZ db.t3.micro)
```

- **ALB를 Terraform이 소유**하는 이유: CloudFront 주소가 EKS 준비와 무관하게 T+20분대에 확정 → 엔드포인트 조기 제출. 파드는 TGB로 나중에 붙는다.
- API 응답이 요청 uuid를 echo하므로 **API는 캐시 불가**(CachingDisabled). 캐시하면 변조로 간주된다. `/images/*`만 CachingOptimized — 채점이 갱신 직후 이미지 내용을 검증해 stale이 문제되면 short-TTL 커스텀 캐시 정책으로 교체(리소스 1개 추가).
- 내부 ALB + VPC Origin → 사용자가 CloudFront를 우회할 경로 없음(엔드포인트 단일화 요구 충족).

## 요구사항 ↔ 구현 매핑

| 요구사항 | 구현 |
|---|---|
| 단일 엔드포인트 | CloudFront (`terraform/cloudfront.tf`) |
| `/images/<key>` 이미지 제공 | `/images/*` behavior + strip Function + OAC (`cloudfront.tf`, `s3.tf`) |
| 비정상 요청 403 | WAF SQLi·KnownBadInputs block, 쿼리스트링 누락 룰 토글 (`waf.tf`) |
| API 외 경로 404 | ALB 리스너 기본액션 fixed-response 404 (`alb.tf`) |
| EKS + EC2 t3.medium만 | NodePool instance-type 고정 (`k8s/01-nodepool.yaml`) |
| 최소 리소스(비용 ratio) | HPA min 2 + Karpenter consolidation → 평시 노드 ~2대, 스파이크 최대 9대(cpu limit 18) |
| DB 최소 운영 | db.t3.micro Multi-AZ 인스턴스 1대 + RDS Proxy (`rds.tf`, `rds-proxy.tf`) |
| SLO 0.2s / 1.0s | RDS Proxy·email 인덱스·CPU limit 제거·선제 HPA (아래 참조) |
| 모니터링·로깅 | amazon-cloudwatch-observability addon (`eksctl/cluster.yaml`) |
| product S3 업로드 | Pod Identity `product-app-sa` + S3FullAccess (`eksctl/cluster.yaml`) |
| Fargate/Lambda 금지 | Auto Mode 노드 = EC2 (관리형이지만 EC2 인스턴스) |

주의: product 앱이 버킷 이름을 어떤 env로 받는지 과제지에 없음 — **당일 바이너리 확인 필수**.
현재 `k8s/02-db-config.yaml`의 `app-config` ConfigMap에 `S3_BUCKET`/`AWS_REGION`으로 넣어두었다
(demo 실측 이름). 이름이 다르면 그 ConfigMap만 고치고 `kubectl rollout restart deploy product`.

## 인스턴스 타입별 튜닝 표

t3.medium(현재) 기준값에서 타입이 바뀌면 아래 행을 그대로 적용한다.
수정 위치는 3곳뿐: ① `k8s/01-nodepool.yaml`의 instance-type values·cpu limit, ② 앱 3파일의 requests, ③ HPA maxReplicas.

| 타입 | vCPU/메모리 | allocatable(약) | max pods | 앱 공통 req (cpu/mem) | HPA max | NodePool cpu limit |
|---|---|---|---|---|---|---|
| **t3.medium** | 2 / 4Gi | 1930m / 3.4Gi | 17 | 600m / 768Mi | 9 | 18 |
| t3.large | 2 / 8Gi | 1930m / 7.2Gi | 35 | 600m / 768Mi | 9 | 18 |
| t3.xlarge | 4 / 16Gi | 3920m / 14.9Gi | 58 | 1200m / 1536Mi | 9 | 36 |
| m5.large / m6i.large | 2 / 8Gi | 1930m / 7.2Gi | 29 | 600m / 768Mi | 9 | 18 |
| c5.large / c6i.large | 2 / 4Gi | 1930m / 3.4Gi | 29 | 600m / 768Mi | 9 | 18 |

**공식** (표에 없는 타입):
- 앱 공통(user·product·stress) cpu request ≈ allocatable × 0.31 — 노드당 3파드 패킹 (demo 실측 600m 기준). memory request=limit는 cpu와 같은 비율(768Mi @3.4Gi).
- NodePool cpu limit = HPA 전체 상한(27파드) × request 를 수용하는 노드 수 × vCPU (t3.medium: 27×600m=16.2 → 9대 → 18)
- HPA max는 유지 — vCPU가 커지면 파드당 request가 커져 노드 수가 줄어드는 구조
- 예상 노드: 최소 2대(min replica 합 3600m + 존 분산), 최대 부하 9대 상한 → 비용 ratio 0.5~3.75 밴드 안

**t 계열 크레딧**: t3는 unlimited 모드가 기본 → 크레딧 소진 후에도 100% 지속 가능(초과분 $0.05/vCPU·h 과금, 4시간 대회에선 무시 가능). baseline은 t3.medium 20%/vCPU, t3.large 30%, t3.xlarge 40%. 확인: `aws ec2 describe-instance-credit-specifications --instance-ids <id>`. m/c 계열은 크레딧 개념 없음(지속 100% 기본).

**성능 원칙 (타입 무관 공통)**:
- **CPU limit 금지** — CFS 스로틀링이 p99를 깎아 0.2s SLO를 직접 해친다. request로만 스케줄링하고 burst는 노드 여유로 흡수.
- memory request=limit 768Mi (demo 실측) — OOM 없이 예측 가능한 패킹. Go 앱 힙은 작지만 여유를 둔다.
- HPA 75% (demo 실측): 파드를 뜨겁게 굴려 파드·노드 수 최소화(비용 ratio). 스케일아웃 리드타임(파드 ~10s, 노드 ~2분)은 scaleUp 공격성으로 흡수.
- scaleUp stabilization 0 + 15s당 최대 4파드/100%: T+60 스텝 트래픽에 즉응. scaleDown 120s + 30s당 50%: 스파이크 종료 후 빠른 회수(비용 ratio) — 120s면 채점 트래픽 재상승도 흡수.

## RDS

- gp3 20GB(baseline 3000 IOPS/125MB·s)로 충분: user 50만행 ≈ 수십 MB → InnoDB 버퍼풀(~375MB)에 전부 상주, 디스크 IOPS는 쓰기 flush뿐. 스토리지 증설은 이 워크로드 성능에 무관.
- db.t3.micro(1GB)의 병목은 **max_connections(~85)와 CPU**. 커넥션은 RDS Proxy 멀티플렉싱으로 해결(파드가 늘어도 백엔드 커넥션 고정). 파라미터 그룹 튜닝은 1GB 메모리에서 얻을 게 없어 기본값 유지.
- **`ALTER TABLE user ADD INDEX idx_email (email)`은 필수** — GET /v1/user?email= 이 유일한 조회 패턴인데 스키마에 email 인덱스가 없다(풀스캔 = SLO 전멸). 과제지의 "테이블 구조 재설계가 필요할 수 있다"가 이것.
- dump 적재는 프록시가 아닌 직결 엔드포인트로(대량 세션이 프록시에 피닝됨).
- **프록시 클라이언트 인증 = MySQL Native** (`client_password_auth_type = MYSQL_NATIVE_PASSWORD`, `rds-proxy.tf`). 제공 앱은 수정 불가이고 TLS를 협상하지 않아 `require_tls=false`인데, MySQL 8.0 기본 `caching_sha2_password`는 평문 연결에서 password 교환이 실패한다 → 앱→프록시 인증을 native로 고정한다. 이에 맞춰 백엔드 `admin` 유저도 `mysql_native_password` 플러그인이어야 하므로 DB 초기화([db/README.md](db/README.md))에서 `ALTER USER ... IDENTIFIED WITH mysql_native_password`로 맞춘다. 엔진이 바뀌면 `client_password_auth_type`가 `locals.tf`의 `db_engine` 삼항으로 자동 파생(postgres → `POSTGRES_SCRAM_SHA_256`).

## 이미지 빌드는 CloudShell에서

- 제공 바이너리 이미지 빌드/푸시(README 4번)는 **ap-northeast-2 CloudShell**에서 수행한다. 워크스테이션은 사설망(private subnet의 RDS 등)에 닿지 않고 로컬 Docker가 없을 수 있는 반면, CloudShell은 Docker 내장(2024-09부터 전 상용 리전) + 인터넷 + ECR 접근을 모두 제공해 in-region으로 push가 끝난다.
- CloudShell은 x86_64 → 제공 바이너리(x86 AL2023 빌드)와 아키텍처가 일치한다. buildkit provenance 매니페스트를 피하려 `docker buildx --push` 대신 classic `docker build`+`docker push`를 쓴다.
- terraform/eksctl/kubectl은 그대로 워크스테이션(본 컴퓨터)에서 실행한다. CloudShell로 옮기는 것은 이미지 빌드 단계 하나뿐이다.

## WAF 운용 기준

| 룰 | 초기 상태 | 근거 |
|---|---|---|
| SQLiRuleSet | **block** | 비정상 요청에 SQLi 포함 확인됨. FP 낮음. block 기본 응답 = 403 |
| KnownBadInputsRuleSet | **block** | log4j 등. FP 극히 낮음 |
| CommonRuleSet | count | NoUserAgent·SizeRestrictions가 채점 트래픽을 오차단할 수 있음 |
| abnormal-v1-missing-token | count (토글) | POST는 requestid가 body에 있을 수 있음 |

전환 판단: WAF 콘솔(us-east-1) sampled requests에서 **정상 채점 트래픽이 매치되지 않는 룰만** block으로. 오차단(availability 하락)이 403 처리율 이득보다 손해가 크다.
- 쿼리스트링 룰: `terraform apply -var waf_v1_block_enabled=true`
- CommonRuleSet 개별 룰: `rule_action_override { name = "<룰명>" action_to_use { block {} } }` 를 waf.tf common 룰에 추가

## TargetGroupBinding 주의

- Auto Mode 전용 스키마: `apiVersion: eks.amazonaws.com/v1`, `targetType: ip` 필수, `spec.networking` 미지원(→ `skills:alb-backend` SG를 NodeClass가 노드에 부착해 ALB→8080 개방).
- 타깃그룹의 `eks:eks-cluster-name` 태그가 없으면 컨트롤러가 타깃 등록 권한이 없다 (alb.tf에서 부여).
- **TGB를 삭제하면 컨트롤러가 타깃그룹을 삭제**할 수 있다 → 타깃그룹이 사라지면 `terraform apply`로 재생성 후 TGB 재적용.

## 당일 변경 시나리오

### ① DB 엔진 교체 (예: MySQL → PostgreSQL) — 약 20분 (RDS 재생성)

1. `terraform/locals.tf`: `db_engine = "postgres"`, `db_engine_version = "17"`(당일 확인), `db_port = 5432`, `db_username = "postgres"` (+ 과제지의 identifier)
2. `terraform -chdir=terraform apply` — DB·프록시만 재생성(engine_family·인증 타입·SG 포트 자동 파생), ALB·CloudFront·EKS는 no-op
3. `k8s/02-db-config.yaml` 키 이름을 새 과제지의 환경변수 표에 맞게 수정 → sed 재적용(README 8번)
4. `kubectl rollout restart deploy user product`
5. DB 초기화([db/README.md](db/README.md))를 새 엔진 클라이언트 이미지로 (`public.ecr.aws/docker/library/postgres:17` + `psql`)

### ② API 추가/삭제 — 약 10분

1. `locals.tf`의 `apps` 맵에 항목 추가/삭제 (path·priority) → `terraform apply` (~1분: ECR·TG·리스너 규칙)
2. `k8s/1X-<app>.yaml` 복사 → 이름·라벨·이미지·TG placeholder 치환 (DB 안 쓰면 envFrom 제거, CPU 바운드면 stress 쪽 수치)
3. 바이너리 빌드/푸시(README 4번) → sed+apply(README 8번)

### ③ 인스턴스 타입 교체 — 약 5분 + 노드 롤링

1. 위 튜닝 표에서 해당 행 확인
2. `k8s/01-nodepool.yaml`: instance-type values·cpu limit 수정 → apply
3. 앱 3파일 requests·HPA max 수정 → apply → 기존 노드는 consolidation이 새 타입으로 교체(PDB가 무중단 보장)
