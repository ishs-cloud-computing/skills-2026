# task-3 설계 근거

## 트래픽 경로

```
사용자 → CloudFront ─┬─ /images/*  → (strip "/images") → S3 (OAC, 캐싱)
        (WAF 403)    └─ 그 외 전부 → ALB(internet-facing) ─┬─ /v1/user    → user 파드
                                                            ├─ /v1/product → product 파드
                                                            ├─ /v1/stress  → stress 파드
                                                            └─ 기본액션    → 404 (fixed-response)
ALB·타깃그룹·리스너 규칙 = AWS Load Balancer Controller가 k8s/20-ingress.yaml 로부터 생성
user/product → RDS Proxy → RDS(Multi-AZ db.t3.micro)
```

## 왜 Auto Mode / TargetGroupBinding 을 버렸나

이전 구성은 EKS Auto Mode + Terraform 소유 ALB + `TargetGroupBinding`(`eks.amazonaws.com/v1`)이었다.
문제는 두 가지였다.

1. **ALB 라우팅이 두 곳으로 쪼개졌다.** 경로·우선순위·타깃그룹은 Terraform(`alb.tf`), 파드 연결은
   k8s(TGB). API를 하나 추가할 때마다 양쪽을 고쳐야 했고 둘의 정합이 깨지면 조용히 404가 났다.
2. **Auto Mode 전용 스키마 의존.** TGB가 `spec.networking`을 지원하지 않아 ALB→파드 8080 개방을
   별도 SG(`skills:alb-backend`)로 만들고 NodeClass의 `securityGroupSelectorTerms`로 노드에
   붙이는 우회책이 필요했다. 타깃그룹에 `eks:eks-cluster-name` 태그가 없으면 컨트롤러가 등록 권한을
   잃는 함정도 있었다.

표준 LBC + Ingress로 바꾸면 라우팅이 `k8s/20-ingress.yaml` 한 파일로 모이고, 백엔드 SG 규칙은
LBC가 직접 관리해 위 우회책 두 개가 통째로 사라진다. Karpenter는 Auto Mode의 관리형 오토스케일러를
대체하며, 대신 NodePool/EC2NodeClass 스키마가 업스트림 표준(`karpenter.sh/v1`,
`karpenter.k8s.aws/v1`)이 된다.

**대가**: ALB를 Ingress가 만들므로 CloudFront가 ALB를 조회하려면 Ingress가 먼저 떠야 한다.
엔드포인트 제출이 T+20 → 약 T+35로 늦어진다(트래픽은 T+60부터라 여유는 있다).
`terraform/cloudfront.tf`의 `data "aws_lb"`가 이 순서 제약의 실체다.

## apply를 1a/1b로 나누는 이유

임계경로는 RDS(~15분)와 EKS(~20분)를 겹치는 데 있다. EKS는 eksctl이 만들고 서브넷 id를
`terraform output`으로 받으므로, 두 작업의 유일한 접점이 **state에 output이 기록된 시점**이다.

네트워크와 RDS를 한 apply로 묶으면 그 apply가 RDS 때문에 15분 블로킹되는데, eksctl은 그보다 먼저
출발해야 병렬이 된다. 즉 **진행 중인 apply의 state에서 output을 읽게 되고**, output 노드가 아직
기록되기 전이면 `Output not found`로 실패한다. 로컬 state가 apply 도중 갱신되는 타이밍에 의존하는 셈이다.

그래서 targeted apply를 네트워크·ECR·S3(1a, ~3분)와 RDS·Proxy(1b, ~15분)로 끊는다. 1a 완료가
"이제 eksctl을 띄워도 된다"는 명시적 신호가 되고, 1b와 eksctl은 각자 자기 창에서 나란히 돈다.
terraform apply는 언제나 한 번에 하나만 도므로 state 락 충돌도 없다. 총 소요는 늘지 않는다 —
3분은 원래 한 덩어리였던 apply의 앞부분이다.

## 요구사항 ↔ 구현 매핑

| 요구사항 | 구현 |
|---|---|
| 단일 엔드포인트 | CloudFront (`terraform/cloudfront.tf`) |
| `/images/<key>` 이미지 제공 | `/images/*` behavior + strip Function + OAC (`cloudfront.tf`, `s3.tf`) |
| 비정상 요청 403 | WAF SQLi·KnownBadInputs block (`waf.tf`) |
| API 외 경로 404 | Ingress `actions.response-404` fixed-response (`k8s/20-ingress.yaml`) |
| EKS + EC2 t3.medium만 | MNG `instanceType` + NodePool instance-type 고정 |
| 최소 리소스(비용 ratio) | 유휴 1대 (아래 전용 절) |
| DB 최소 운영 | db.t3.micro Multi-AZ 인스턴스 1대 + RDS Proxy (`rds.tf`, `rds-proxy.tf`) |
| SLO 0.2s / 1.0s | RDS Proxy·email 인덱스·CPU limit 제거·선제 HPA |
| 모니터링·로깅 | metrics-server + WAF 로그 Logs Insights (`queries/`, NOTES.md) — 앱 stdout은 `kubectl logs` |
| product S3 업로드 | Pod Identity `product` SA + S3FullAccess (`eksctl/cluster.yaml`) |
| Fargate/Lambda 금지 | MNG·Karpenter 노드 모두 EC2 |

주의: product 앱이 버킷 이름을 어떤 env로 받는지 과제지에 없음 — **당일 바이너리 확인 필수**
(README STEP 3c에서 확정한다). 현재 `k8s/11-product.yaml`에 `S3_BUCKET`/`AWS_REGION`으로 넣어두었다.

env는 공용 ConfigMap/Secret 대신 각 앱 매니페스트에 직접 둔다: 채점이 블랙박스라 이들을
검사하지 않고, 계정도 1회성이라 Secret의 이점이 없으며, 앱마다 env가 달라 자기완결적 파일이
당일 변경에 안전하기 때문. 값은 README STEP 6에서 치환.

## 유휴 EC2 = 1대

비용 ratio(12점)의 전제. 트래픽이 없을 때 running EC2는 t3.medium **1대**다.
노드 수를 밀어올리는 요인 네 개를 각각 제압한다.

| # | 요인 | 조치 | 위치 |
|---|---|---|---|
| 1 | 부트스트랩 노드그룹 | MNG `min=desired=max=1` | `eksctl/cluster.yaml` |
| 2 | Karpenter 차트 기본 `replicas: 2` + 하드 podAntiAffinity(hostname) + zone spread `DoNotSchedule` | `kubectl -n karpenter scale deploy/karpenter --replicas=1` | README STEP 4 |
| 3 | LBC 차트 기본 `replicaCount: 2` | `helm ... --set replicaCount=1` | README STEP 4 |
| 4 | 앱 zone spread `DoNotSchedule` | `ScheduleAnyway` | `k8s/1X-*.yaml` |
| 5 | Karpenter 노드가 유휴에도 남음 | `consolidationPolicy: WhenEmptyOrUnderutilized`, `consolidateAfter: 30s` | `k8s/01-nodepool.yaml` |

**2번은 순서가 중요하다.** Karpenter replica 축소는 **NodePool을 apply하기 전에** 한다. NodePool이
없으면 Karpenter는 아무것도 프로비저닝할 수 없어 Pending인 2번째 replica가 노드를 유발하지 않는다.
순서를 뒤집으면 Karpenter가 자기 자신을 위해 노드를 띄우고, 축소 후 consolidation이 회수할 때까지
EC2가 2대다.

**PodDisruptionBudget을 삭제한 이유**: `minAvailable: 1` + HPA `minReplicas: 1` 조합은 단일 파드의
축출을 영구히 막아 Karpenter consolidation을 정지시킨다 — 유휴에도 노드가 안 줄어든다.
블라스트 반경은 NodePool의 `disruption.budgets: nodes "1"`이 이미 제한한다.

### t3.medium 1대 용량 검산 (allocatable ≈ 1930m CPU / 3.4Gi / max 17 pods)

| 구성요소 | CPU req | Mem req | pods |
|---|---|---|---|
| kube-proxy + aws-node(+nodeagent) | ~150m | ~150Mi | 2 |
| coredns ×2 | 200m | 140Mi | 2 |
| metrics-server | 100m | 200Mi | 1 |
| karpenter ×1 / LBC ×1 | 0 (두 차트 모두 기본 requests 없음) | — | 2 |
| cloudwatch-agent + fluent-bit (DaemonSet) | ~300m | ~400Mi | 2 |
| **시스템 소계** | **~750m** | **~0.9Gi** | **9** |
| 앱 3종 × min 1 × 250m/512Mi | 750m | 1.5Gi | 3 |
| **합계** | **~1500m / 1930m** | **~2.4Gi / 3.4Gi** | **12 / 17** |

여유 ~430m. 실제로 안 들어가면(파드가 Pending) 조정 순서:
① `kubectl -n kube-system scale deploy/coredns --replicas=1` → ② 앱 requests 200m로
→ ③ MNG를 2대로. 확인 명령은 README STEP 10.

**감수하는 것**: 노드 1대는 단일 장애점이다. 그 노드가 죽으면 MNG가 재기동할 때까지(~2분) 전면
중단된다. 채점이 비율(availability %)이고 비용 ratio 배점이 12점이라 1대를 택했다.

**주의 — 비용 ratio에는 하한이 있다.** 채점 기준은 `0.5 <= ratio <= X` 형태라 **ratio가 0.50 미만이면
12점 전부 0점**이다. 싸게 만들수록 좋은 단조 함수가 아니다. 유휴 1대는 그 하한에 가까워지는 방향이고,
부하 구간의 스케일아웃(최대 7대)이 평균을 끌어올려 밴드 안에 들어오는 구조다. 당일 트래픽이 예상보다
약해 스케일아웃이 거의 안 일어나면 하한을 밑돌 수 있으므로, T+60 이후 `kubectl get nodeclaims`로
노드가 실제로 증가하는지 확인한다. 전혀 안 늘면 HPA 목표치를 60% → 40%로 낮춰 파드·노드를 늘린다.
(반대로 배점 상한 3.75는 여유가 크므로 과다 회수보다 과소 회수가 안전한 쪽이다.)

## 인스턴스 타입별 튜닝 표

t3.medium(현재) 기준값에서 타입이 바뀌면 아래 행을 그대로 적용한다.
수정 위치는 4곳: ① `eksctl/cluster.yaml`의 MNG `instanceType`, ② `k8s/01-nodepool.yaml`의
instance-type values·cpu limit, ③ 앱 3파일의 requests, ④ HPA maxReplicas.

| 타입 | vCPU/메모리 | allocatable(약) | max pods | 앱 공통 req (cpu/mem) | HPA max | NodePool cpu limit |
|---|---|---|---|---|---|---|
| **t3.medium** | 2 / 4Gi | 1930m / 3.4Gi | 17 | 250m / 512Mi | 10 | 12 |
| t3.large | 2 / 8Gi | 1930m / 7.2Gi | 35 | 250m / 512Mi | 10 | 12 |
| t3.xlarge | 4 / 16Gi | 3920m / 14.9Gi | 58 | 500m / 1Gi | 10 | 24 |
| m5.large / m6i.large | 2 / 8Gi | 1930m / 7.2Gi | 29 | 250m / 512Mi | 10 | 12 |
| c5.large / c6i.large | 2 / 4Gi | 1930m / 3.4Gi | 29 | 250m / 512Mi | 10 | 12 |

**공식** (표에 없는 타입):
- 앱 공통 cpu request ≈ allocatable × 0.13 — 시스템 파드를 뺀 여유에 앱을 촘촘히 패킹.
  memory request=limit는 cpu와 같은 비율(512Mi @3.4Gi).
- NodePool cpu limit = HPA 전체 상한(3앱 × 10 = 30파드) × request 를 수용하는 노드 수 × vCPU.
  t3.medium: 30 × 250m = 7.5 vCPU → DS 오버헤드 감안 6대 → 12.
- HPA max는 유지 — vCPU가 커지면 파드당 request가 커져 노드 수가 줄어드는 구조.
- 예상 노드: 유휴 1대(MNG) → 최대 부하 1 + 6 = 7대 → 비용 ratio 0.5~3.75 밴드 안.

**t 계열 크레딧**: t3는 unlimited 모드가 기본 → 크레딧 소진 후에도 100% 지속 가능(초과분
$0.05/vCPU·h, 4시간 대회에선 무시 가능). baseline은 t3.medium 20%/vCPU, t3.large 30%, t3.xlarge 40%.
확인: `aws ec2 describe-instance-credit-specifications --instance-ids <id>`.

**성능 원칙 (타입 무관 공통)**:
- **CPU limit 금지** — CFS 스로틀링이 p99를 깎아 0.2s SLO를 직접 해친다. request로만 스케줄링하고
  burst는 노드 여유로 흡수. 이 때문에 request를 작게 잡아도(250m) 실제 처리량은 그보다 크다.
- memory request=limit 512Mi — OOM 없이 예측 가능한 패킹.
- HPA 60%: 스케일아웃 리드타임(파드 ~10s, 노드 ~2분)을 감안한 여유. 파드를 지나치게 뜨겁게 굴리면
  p99가 무너져 성능 효율성(12점)을 잃는다.
- scaleUp stabilization 0 + 15s당 최대 4파드/100%: T+60 스텝 트래픽에 즉응.
  scaleDown 40s + 40s당 50%: 스파이크 종료 후 빠른 회수(비용 ratio).

## Karpenter 주의

- **버전 고정**: `eksctl/cluster.yaml`의 `karpenter.version`. k8s 1.36은 Karpenter **>= 1.13**이
  필요하다(호환성 매트릭스). 대회 당일 최신 stable을 확인해 갱신한다.
  eksctl은 **하한(0.28.0)만** 검사하고 상한은 없다 — 실패하면 그 버전의 Helm 차트가 없다는 뜻이다.
  (검증 시점: eksctl 0.229.0 / Karpenter 1.14 / k8s 1.36)
- **eksctl이 만들어 주는 것**: 컨트롤러 IRSA(`iam.withOIDC: true` 필수 — 저장소에 IRSA가 남는
  유일한 지점이다. 나머지 SA는 전부 Pod Identity),
  노드 IAM 역할 `eksctl-KarpenterNodeRole-<cluster>`, 인스턴스 프로파일, 노드롤 access entry,
  Helm 설치. EC2NodeClass의 `role` 값이 이 이름 규칙을 따른다.
- **discovery 태그가 세 곳에서 일치해야 한다**: `terraform/vpc.tf`의 private subnet 태그,
  `eksctl/cluster.yaml`의 `metadata.tags`, `k8s/00-nodeclass.yaml`의 selector.
  eksctl은 `metadata.tags`에 이 태그가 있을 때만 공유 노드 SG를 자동 태깅한다 —
  없으면 `securityGroupSelectorTerms`가 아무것도 못 찾아 노드가 안 뜬다.
- MNG 노드는 Karpenter가 관리하지 않는다(consolidation 대상 아님). 그래서 MNG를 1대로 고정한다.

## AWS Load Balancer Controller 주의

- **EKS 관리형 addon이 아니다.** Helm 차트로만 설치된다 → 대회 PC에 `helm.exe`가 필요하다.
  (검증 시점: 차트 `eks/aws-load-balancer-controller` 3.5.0 / appVersion v3.5.0)
- Gateway API는 차트 기본값에서 **꺼져 있다**(`controllerConfig.featureGates`의 `ALBGatewayAPI`·
  `NLBGatewayAPI`가 미설정). Ingress만 쓰므로 Gateway API CRD를 따로 설치할 필요가 없다.
- 차트는 `replicaCount > 1`일 때만 PDB를 만든다 → `replicaCount=1`이면 PDB도 안 생겨
  노드 드레인을 막지 않는다.
- IAM은 eksctl `iam.podIdentityAssociations[].wellKnownPolicies.awsLoadBalancerController: true`로
  만든다. 공식 문서의 `curl iam_policy.json` + `aws iam create-policy` 두 단계가 사라진다(Windows에서
  유리). Helm은 `serviceAccount.create=false`로 그 SA를 재사용한다 — Pod Identity는 SA에 붙일
  annotation이 없어 IRSA보다 오히려 단순하다. 인증 실패 시 증상은 Ingress ADDRESS가 안 차는 것이고,
  `kubectl -n kube-system logs deploy/aws-load-balancer-controller`의 AccessDenied로 구분한다.
- **서브넷 auto-discovery**: internet-facing ALB는 **퍼블릭 서브넷의 `kubernetes.io/role/elb` 태그**로
  찾는다(`terraform/vpc.tf`). 이 태그가 없으면 Ingress의 ADDRESS가 영원히 비어 있다 —
  ALB가 안 뜰 때 제일 먼저 확인할 곳.
- `load-balancer-name` 어노테이션 값은 `terraform/locals.tf`의 `alb_name`과 **반드시 같아야 한다**.
  `cloudfront.tf`의 `data "aws_lb"`가 이 이름으로 조회한다.
- `defaultBackend`의 서비스 포트 이름이 `use-annotation`이면 그 이름의 Service는 실재하지 않아도
  된다 — `actions.response-404` 어노테이션이 리스너 기본 액션이 된다.
- 백엔드 SG 규칙(ALB→파드 8080)은 LBC가 노드 SG에 직접 넣는다. 별도 SG를 만들 필요가 없다.

## 파일 간 결합 (당일 수정 시 함께 봐야 하는 짝)

당일 값을 바꿀 때 한쪽만 고치면 조용히 깨지는 지점들이다.

| 값 | A | B | C |
|---|---|---|---|
| ALB 이름 | `terraform/locals.tf` `alb_name` | `k8s/20-ingress.yaml` `load-balancer-name` | — |
| 클러스터 이름 | `terraform/locals.tf` `cluster_name` | `eksctl/cluster.yaml` `metadata.name` | `k8s/00-nodeclass.yaml` `role`, helm `--set clusterName` |
| discovery 태그 | `terraform/vpc.tf` private subnet | `eksctl/cluster.yaml` `metadata.tags` | `k8s/00-nodeclass.yaml` selector 2곳 |
| 앱 목록 | `terraform/variables.tf` `apps` (ECR) | `k8s/1X-<app>.yaml` (Deploy/Svc/HPA) | `k8s/20-ingress.yaml` path 블록 |
| Service 이름 | `k8s/1X-<app>.yaml` Service | `k8s/20-ingress.yaml` backend | — |
| 이미지 태그 | `terraform/variables.tf` `image_tag` | README STEP 3의 `TAG` | — |

## RDS

- gp3 20GB(baseline 3000 IOPS/125MB·s)로 충분: user 50만행 ≈ 수십 MB → InnoDB 버퍼풀(~375MB)에
  전부 상주, 디스크 IOPS는 쓰기 flush뿐.
- db.t3.micro(1GB)의 병목은 **max_connections(~85)와 CPU**. 커넥션은 RDS Proxy 멀티플렉싱으로
  해결(파드가 늘어도 백엔드 커넥션 고정). 파라미터 그룹 튜닝은 1GB 메모리에서 얻을 게 없다.
- **`ALTER TABLE user ADD INDEX idx_email (email)`은 필수** — `GET /v1/user?email=`이 유일한 조회
  패턴인데 과제지 스키마에 email 인덱스가 없다(풀스캔 = SLO 전멸). 과제지의 "테이블 구조 재설계가
  필요할 수 있다"가 이것. `db/02-index.sql`.
- dump 적재는 프록시가 아닌 직결 엔드포인트로(대량 세션이 프록시에 피닝됨).
- **프록시 클라이언트 인증 = MySQL Native** (`client_password_auth_type = MYSQL_NATIVE_PASSWORD`,
  `rds-proxy.tf`). 제공 앱은 수정 불가이고 TLS를 협상하지 않아 `require_tls=false`인데, MySQL 8.0
  기본 `caching_sha2_password`는 평문 연결에서 password 교환이 실패한다 → 앱→프록시 인증을 native로
  고정한다. 이에 맞춰 백엔드 `admin` 유저도 `mysql_native_password`여야 한다(README STEP 8-2).
  엔진이 바뀌면 `locals.tf`의 `db_engine` 삼항으로 자동 파생(postgres → `POSTGRES_SCRAM_SHA_256`).
- **DB 초기화 순서 = 스키마 → ALTER USER → dump → 인덱스.** 앞의 둘은 즉시 끝나면서 앱·프록시 연결의
  하드 전제조건이고, dump 적재만 느리다. 스키마·인증이 끝난 시점에 앱 배포(README STEP 6)를 병행하면
  노드 생성·파드 기동·타깃 등록이 dump 적재와 겹친다. dump→인덱스 순서는 유지(dump가 DROP/CREATE
  TABLE을 포함할 수 있고, InnoDB 벌크 적재 후 세컨더리 인덱스 생성이 더 빠르다).

## 이미지 빌드는 CloudShell에서

- 제공 바이너리 이미지 빌드/푸시(README STEP 3)는 **ap-northeast-2 CloudShell**에서 수행한다.
  Docker 내장 + 인터넷 + ECR 접근을 모두 제공해 in-region으로 push가 끝난다. CloudShell은 x86_64라
  제공 바이너리(x86 AL2023 빌드)와 아키텍처가 일치한다. buildkit provenance 매니페스트를 피하려
  `docker buildx --push` 대신 classic `docker build`+`docker push`를 쓴다.
- **베이스는 `distroless/base`(glibc 포함), `static` 아님.** 과제지가 바이너리를 AL2023 기본
  빌드(cgo on)라고 명시하므로 Gin의 `net`·`os/user`가 cgo resolver를 끌어와 glibc에 동적 링크될
  가능성이 높다. 불일치 시 `exec /app/server: no such file or directory`로 즉사하며, 이 메시지는
  없는 것이 바이너리가 아니라 ELF 인터프리터라는 사실을 감춘다. `base`는 ~18MB로 이 분기를 산다.
- **push 전에 앱을 검증한다(README STEP 3a–3c).** STEP 9의 CloudFront 스모크는 CF·WAF·ALB·파드
  4개 레이어 너머라 앱 결함과 인프라 결함이 구분되지 않는다. CloudShell에서 `file` + `docker run` +
  로컬 mysql:8.0으로 부팅·포트·healthcheck·env 키·PUT 멀티파트 필드명·S3 오브젝트 키를 먼저 확정한다.

## 보안 범위

3과제 채점은 전부 블랙박스(응답코드·응답시간·비용)다. 과제지가 명시하지 않은 보안 장치는 넣지 않는다.
실제로 걷어낸 것:

- ALB SG를 CloudFront 관리형 prefix list로 잠그던 구성 → 삭제. LBC가 만드는 기본 SG(0.0.0.0/0:80)를
  쓴다. 필요하면 `k8s/20-ingress.yaml`의 `security-group-prefix-lists` 한 줄만 주석 해제한다
  (값은 `terraform output cloudfront_prefix_list_id`).
- `aws_s3_bucket_public_access_block` → 삭제. 2023-04 이후 신규 버킷 기본값과 동일하다.

**남긴 것과 이유**:
- **WAF** — "비정상 요청 403"이 채점 항목(1-5~1-8) 자체다. 보안이 아니라 기능이다.
- **S3 버킷 정책(OAC)** — 퍼블릭 버킷 없이 `/images/*`를 제공하기 위한 OAC 동작 조건이다.
- **RDS/Proxy SG, Secrets Manager** — RDS Proxy의 하드 요구사항이다.

## WAF 운용 기준

| 룰 | 상태 | 근거 |
|---|---|---|
| SQLiRuleSet | **block** | 비정상 요청에 SQLi 포함 확인됨. FP 낮음. block 기본 응답 = 403 |
| KnownBadInputsRuleSet | **block** | 헤더/프로토콜 변조·log4j 등. FP 극히 낮음 |

두 관리형 룰만 block으로 둔다. CommonRuleSet은 NoUserAgent·SizeRestrictions 등이 정상 채점
트래픽을 오차단할 수 있어(availability 12점 손실이 Exception Handling 2점 이득보다 크다) 기본
구성에서 뺐다.

**당일 User-Agent 계열 비정상 요청이 관측되면** 아래를 `waf.tf`에 추가한다 — CommonRuleSet을 넣되
`NoUserAgent_HEADER`만 block으로 두고 오차단 위험군은 전부 count로 내린다.

```hcl
rule {
  name     = "common-ua-only"
  priority = 30

  override_action {
    none {}
  }

  statement {
    managed_rule_group_statement {
      vendor_name = "AWS"
      name        = "AWSManagedRulesCommonRuleSet"

      # NoUserAgent_HEADER 만 block. 나머지는 count로 내려 오차단을 막는다.
      # 당일 콘솔의 룰 목록을 보고 필요한 이름을 여기에 계속 추가한다.
      dynamic "rule_action_override" {
        for_each = toset([
          "SizeRestrictions_BODY", "SizeRestrictions_QUERYSTRING", "SizeRestrictions_URIPATH",
          "SizeRestrictions_Cookie_HEADER", "CrossSiteScripting_BODY", "CrossSiteScripting_COOKIE",
          "CrossSiteScripting_QUERYARGUMENTS", "CrossSiteScripting_URIPATH",
          "GenericLFI_BODY", "GenericLFI_QUERYARGUMENTS", "GenericLFI_URIPATH",
          "GenericRFI_BODY", "GenericRFI_QUERYARGUMENTS", "GenericRFI_URIPATH",
          "EC2MetaDataSSRF_BODY", "EC2MetaDataSSRF_COOKIE",
          "EC2MetaDataSSRF_QUERYARGUMENTS", "EC2MetaDataSSRF_URIPATH",
          "RestrictedExtensions_URIPATH", "RestrictedExtensions_QUERYARGUMENTS",
          "UserAgent_BadBots_HEADER", "LFI_URIPATH",
        ])
        content {
          name = rule_action_override.value
          action_to_use {
            count {}
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "common-ua-only"
    sampled_requests_enabled   = true
  }
}
```

## 당일 변경 시나리오

### ① DB 엔진 교체 (예: MySQL → PostgreSQL) — 약 20분 (RDS 재생성)

1. `terraform/locals.tf`: `db_engine = "postgres"`, `db_engine_version`(당일 확인), `db_port = 5432`,
   `db_username = "postgres"` (+ 과제지의 identifier)
2. `terraform -chdir=terraform apply` — DB·프록시만 재생성(engine_family·인증 타입·SG 포트 자동 파생),
   CloudFront·EKS는 no-op
3. `k8s/10-user.yaml`·`k8s/11-product.yaml`의 env 키 이름을 새 과제지 표에 맞게 수정 → 재적용(STEP 6)
4. `kubectl rollout restart deploy user product`
5. DB 초기화는 CloudShell에서 새 엔진 클라이언트로 (`sudo dnf install -y postgresql16` →
   `psql -h <endpoint> -U postgres`)

### ② API 추가/삭제 — 약 10분

1. `terraform/variables.tf`의 `apps` 목록에 항목 추가/삭제 → `terraform apply` (~1분: ECR만)
2. `k8s/1X-<app>.yaml` 복사 → 이름·라벨·이미지 placeholder 수정 (DB 안 쓰면 env 블록 제거)
3. `k8s/20-ingress.yaml`에 path 블록 하나 추가 → apply (LBC가 리스너 규칙·타깃그룹을 자동 생성)
4. 바이너리 빌드/푸시(STEP 3) → 치환+apply(STEP 6)

### ③ 인스턴스 타입 교체 — 약 5분 + 노드 롤링

1. 위 튜닝 표에서 해당 행 확인
2. `eksctl/cluster.yaml` MNG `instanceType` 수정 → `eksctl update nodegroup` 또는 노드그룹 재생성
3. `k8s/01-nodepool.yaml`: instance-type values·cpu limit 수정 → apply
4. 앱 3파일 requests·HPA max 수정 → apply → 기존 Karpenter 노드는 consolidation이 새 타입으로 교체
