# set-06 / task-1

개발자용 기록. 실행 절차는 [README.md](README.md), 설계 근거는 아래 「설계」 절.

## 현재 상태

- `terraform/` · `eksctl/` · `k8s/` · `app/` 구현 완료. 마지막 실측 배포는 **2026-07-23**(구 `set-06/task-1` 브랜치 시점).
- 2026-08-29 main 으로 편입하면서 런북을 set-07/task-1 형식으로 재작성하고 `plan.md`·Astro 사이트를 이 문서로 합쳤다.
  이어서 **컨테이너 이미지 작업을 전부 일반 CloudShell 로 옮겼다**(본 PC Docker Desktop 의존 제거).
  **재작성된 런북은 실제 배포로 재검증되지 않았다** — 아래 「미검증」 참고.
- set-06 은 `DAY-OF.md`·`KIT-INDEX.md`·`QUICK-REFERENCE.md`·`NAMING-AUDIT.md` 에 **등재돼 있지 않다.**
  네 문서 모두 2026-08-19 런북 동결 대상이라 이 편입에서 건드리지 않았다. 값 대조표는 README 가 자체로 들고 있다.

## 채점 커버리지

`mark.sh` 25항목 기준. **아래 판정은 편입 시점의 코드 대조이며 재배포 검증은 하지 않았다**
(마지막 실측은 2026-07-23). `[x]` 완료 · `[~]` 부분·조건부 · `[ ]` 미완.

| 항목 | 내용 | 판정 | 근거 |
|---|---|:--:|---|
| 1-1-A | VPC | [x] | `terraform/vpc.tf` — `10.0.0.0/16`, priv 2AZ |
| 1-2-A | Route Table | [x] | `terraform/vpc.tf` — Gateway Endpoint 라우트는 `DestinationCidrBlock` 키가 없어 출력에 안 섞인다 (§0-2) |
| 1-3-A | NAT Gateway | [x] | `terraform/vpc.tf` — NAT 미생성이 요구사항 (§3.1) |
| 2-1-A | ECR Repository | [x] | `terraform/ecr.tf` — `book` + direct + PTC 규칙 |
| 2-2-A | ECR Image Size ≤ 3MB | [~] | `app/Dockerfile` — UPX 선압축 + zstd. **빌드해봐야 확정된다**, 런북 2단계가 크기를 출력한다 (§3.3) |
| 3-1-A | DynamoDB Configuration | [x] | `terraform/dynamodb.tf` — `books`, PK `booking_id`, GSI `client_id-index` |
| 3-2-A | DynamoDB Encryption | [x] | `terraform/dynamodb.tf` + `kms.tf` `alias/gj2026-db-key` |
| 3-3-A | DynamoDB Access Restrictions | [~] | `terraform/dynamodb.tf` 리소스 정책 + `var.enable_ddb_write_deny`. **Deny 전파 확인까지** 끝나야 성립 (§3.4, 함정 37) |
| 4-1-A | EKS Configuration | [x] | `eksctl/cluster.yaml` — 1.35, service CIDR `172.20.0.0/16` |
| 4-2-A | NodeGroup Configuration | [x] | `eksctl/cluster.yaml` — NG 2개, `amiFamily: Bottlerocket`(ami 지정 금지), desired 2 |
| 4-3-A | Node Naming Convention | [~] | `eksctl/bootstrap/set-hostname-*.sh` + aws-auth 매핑. **인증 전환 순서를 지켜야만** 성립 (§3.5.2) |
| 4-4-A | Application Pods | [x] | `k8s/app/02-deployment.yaml` |
| 4-5-A | Network Policy (Pod SG) | [~] | `k8s/app/04-securitygrouppolicy.yaml`. `ENABLE_POD_ENI=true` 를 Pod 생성 **전에** 걸어야 하고, PTC 워밍업(nginx) 필요 (§3.6.1) |
| 5-1-A | ALB Configuration | [x] | `terraform/alb.tf` — `gj2026-alb`, TG 2종 |
| 6-1-A | S3 Object Existence | [x] | `terraform/s3.tf` — `shared/provided/set-06-task-1/` 를 직접 업로드 |
| 6-2-A | S3 Encryption | [x] | `terraform/s3.tf` + `alias/gj2026-s3-key` |
| 7-1-A | Lambda Configuration | [x] | `terraform/lambda.tf` — `gj2026-book-reservation`, `python3.14` |
| 8-1-A | S3 Static Content | [x] | `terraform/cloudfront.tf` — s3 origin + `gj2026-rewrite-index` 함수 |
| 8-2-A | ALB API | [~] | `k8s/app/*` + `app/Dockerfile`. scratch 이미지 CA 부재·SGP DNS 차단이 실패 원인이었다 (함정 27/28/35) |
| 8-3-A | Lambda API 1 (전체 2건) | [~] | `terraform/lambda/index.py`. **`books` 가 0건인 상태에서 채점을 시작해야** 개수가 맞는다 |
| 8-4-A | Lambda API 2 (C001 1건) | [~] | 같은 위 — 잔여 데이터가 있으면 깨진다 |
| 9-1-A | HTTP Method Restriction | [x] | `terraform/waf.tf` 룰 `deny-non-post-on-api` |
| 9-2-A | Query String Restriction | [x] | `terraform/waf.tf` 룰 `deny-invalid-client-id` + `var.client_id_regex`(앵커 필수, §3.10) |
| 10-1-A | Fluent Bit (스트림 정확히 2개) | [~] | `k8s/logging/fluent-bit-values.yaml` — 차트 기본 output(`Match "*"`) 비활성, 파싱 실패 레코드가 3번째 스트림을 만든다 (§3.11) |
| 10-2-A | Grafana Dashboard | [~] | `k8s/monitoring/*`. **수동 채점** — 8-3 실행 시각에 `ALL`·`C001` 두 시리즈가 찍혀야 한다 |

`[~]` 11건은 코드가 아니라 **실행 순서·상태**에 걸린 항목이다. README 5·8·9단계가 그 순서를 강제한다.

## 실측 소요시간

| 단계 | 시간 |
|---|---|
| terraform apply (CloudFront 포함) | 최대 15분 |
| eksctl create cluster (desired 0) | 15~20분 |
| scale-up → 노드 4개 Ready | 2~5분 |
| 노드그룹만 재시도 (NodeCreationFailure) | 5~7분 (클러스터 재생성은 20분+) |
| CloudFront invalidation | 최대 3분 |
| terraform destroy | CloudFront 삭제에 15분 전후 |

## 미검증

배포로 확인하지 못한 것들. 대회 전에 한 번은 돌려봐야 한다.

- **2026-08-29 재작성한 런북 전체.** set-07 형식으로 옮기면서 `.env.ps1` 을 키 목록 기반 재작성으로,
  k8s apply 를 `rendered/` 일괄 방식으로 바꿨다. 명령 자체는 등가지만 실행으로 확인하지 않았다.
- **일반 CloudShell 이미지 경로(2단계) 전체.** 본 PC Docker Desktop 의존을 없애려고 옮겼지만
  한 번도 돌려보지 않았다. 특히 확인이 필요한 전제 셋:
  1. **CloudShell 의 `docker buildx` + zstd 출력 지원.** 채점 2-2(3MB)가 여기에 통째로 걸린다.
     `docker buildx version` 이 실패하면 zstd 출력이 안 되고 3MB 를 못 맞춘다.
     그 경우의 대안은 ① 본 PC 에서 Docker 를 쓸 수 있으면 2단계만 본 PC 로 되돌리거나,
     ② CloudShell 에 buildx 플러그인을 직접 설치하는 것이다. 둘 다 미검증.
  2. **CloudShell 디스크 여유.** grafana(수백 MB)를 포함해 이미지 5종을 다루므로 pull→tag→push→`rmi`
     순서로 하나씩 비우도록 써 뒀다. 그래도 모자라면 `docker system prune -af`.
  3. **Docker Hub 익명 pull 레이트 리밋.** grafana 만 Docker Hub 다 — `toomanyrequests` 가능.
- 아래 「6.2 문서로 확정 안 된 항목」의 잔여 항목.

## 결정 로그

### 2026-08-29 컨테이너 이미지 작업을 전부 일반 CloudShell 로 이전

바로 아래 「런북을 set-07/task-1 형식으로 재작성」 항목에서 **기각했던 머신 3분할의 절반을 뒤집는다.**

- **맥락**: 재작성 직후의 런북은 2단계(book 빌드)와 4단계(미러·PTC 워밍업)가 본 PC Docker Desktop
  전제였다. 저장소 공통 전제는 「대회 PC 는 Docker·WSL 사용 불가」(`.claude/context/contest.md`)이므로
  그대로 두면 대회장에서 2·4단계가 아예 실행되지 않는다. set-07 은 같은 이유로 빌드를 CloudShell 에 둔다.
- **채택**: 이미지 관련 명령을 **일반 CloudShell**(VPC environment 아님) 한 단계로 합쳤다.
  기존 2·4단계 → 새 2단계, 이후 단계는 하나씩 당겨 5~9 → 4~8 로 번호가 바뀌었다.
  제공 바이너리는 **S3 릴레이**(`_transfer/` 접두어)로 넘기고, 그래서 1단계가 `aws_s3_bucket.static`
  까지 먼저 만든다. `Dockerfile` 은 텍스트라 붙여넣는다(줄 수 17 대조).
- **기각**: ① 일반 CloudShell 의 Actions 업로드 UI 로 바이너리 전달 — 되긴 하지만 set-07 과 절차가
  갈리고 정책으로 막힐 수 있다. ② VPC environment 도입 — set-06 은 클러스터 엔드포인트가 public 이라
  `kubectl`·`helm` 이 본 PC 에서 되므로 필요 없다. 이 절반은 여전히 기각 상태다.
- **대가**: ① CloudShell 의 `docker buildx`·zstd 지원이 새 전제가 됐다(「미검증」 1번).
  ② 릴레이 객체가 채점 대상 버킷에 잠시 얹힌다 — 채점 6-1-A 는 `/` 없는 키만 세므로 영향이 없고,
  7단계에서 지운다.

### 2026-08-29 `plan.md` 와 Astro 사이트를 NOTES.md 하나로 합침

- **맥락**: 구 `set-06/task-1` 브랜치는 main 과 공통 조상이 없는 평행 트리였고, 설계 문서가
  `plan.md`(70KB) 와 `site/`(Astro Starlight, `package-lock.json` 250KB 포함) 두 곳에 있었다.
  `site/` 는 `plan.md` 를 페이지 단위로 쪼갠 파생본이라 내용이 같다(구 `plan.md` §8 이 그 이관 계획).
- **채택**: `set-06/task-1/` 만 main 위로 가져오고, `plan.md` 본문을 이 문서 「설계」 절로 편입.
  `site/` 와 `log.txt` 는 버렸다. 코드 주석 60곳의 `plan.md §X` 참조는 `NOTES.md §X` 로 바꿨고
  **§ 번호는 그대로 유지**해 참조가 계속 맞는다.
- **기각**: ① 브랜치 통째 머지 — 공통 조상이 없어 main 의 거의 모든 파일이 충돌하고 `docs/`·`mise.toml`·
  `netlify.toml` 과 다른 세트의 옛 버전까지 되돌아온다. ② `site/` 유지 — 저장소에 문서 사이트를 두지
  않는다는 규약(`.claude/context/layout.md`)과 충돌하고, 같은 내용이 두 곳에 남아 갈라진다.
- **대가**: 발행용 Starlight 페이지가 사라진다. 필요해지면 학습 가이드 저장소 쪽에서 다시 만든다.

### 2026-08-29 런북을 set-07/task-1 형식으로 재작성

- **맥락**: set-06 런북은 `## N.` 평면 목록이라 실행 위치(본 PC / CloudShell)가 제목에 안 드러나고,
  값 대조표·요구사항↔구현 매핑·teardown 절차·주의 포인트가 없었다.
- **채택**: set-07 의 뼈대(값 대조표 → 디렉토리 구조 → `### N) [실행 위치]` 단계 → teardown 표 + T 단계 →
  매핑 → 검증 시드 → 주의)를 입히고, 명령 관례도 set-07 쪽으로 맞췄다 —
  `.env.ps1` 을 키 목록에서 통째로 재작성(변수 추가 시 누락 방지), k8s 를 `rendered/` 일괄 apply 후
  잔여 `${}` 검사, 이미지 태그 존재 확인 추가.
- **기각**: set-07 의 **머신 3분할**(일반 CloudShell 빌드 + `unicorn-mark` VPC environment) 이식.
  set-06 은 클러스터 엔드포인트가 public 이라 본 PC 에서 `kubectl` 이 되고 VPC environment 가 필요 없다.
  빌드도 PTC·미러 워밍업과 묶여 있어 셸만 옮길 수 없다 — 옮기려면 이미지 공급 경로 전체를 다시 설계해야 한다.
- **대가**: Docker 전제가 그대로 남는다. README 「배포 순서」와 위 「미검증」에 경고로 남겼다.

### 2026-08-29 제공 배부물을 저장소에서 제외

- **맥락**: 구 브랜치는 `shared/provided/set-06-task-1/` 에 `book-linux-amd64_v1.0.1`·`index.html`·`main.jpeg`
  를 커밋해 뒀다. main 은 배부물을 git 에서 제거하는 방침이다(f395d62, 2988555).
- **채택**: 파일은 가져오지 않고 `.gitkeep` 만 두었다. `.gitignore` 에 경로를 추가했고 런북이 로컬 배치를 지시한다.
- **대가**: 클론 직후에는 2단계 빌드와 `s3.tf` 업로드가 실패한다. 런북 「디렉토리 구조」에 명시했다.

---

## 설계

> 아래는 구 `plan.md` 본문이다. **§ 번호는 코드 주석 60곳이 가리키는 앵커라 바꾸지 않는다.**

EKS(Bottlerocket) 위에 Book API를 배포하고, CloudFront 단일 엔드포인트로 S3 정적 페이지 · ALB API · Lambda 조회 API · Grafana를 함께 서비스하는 과제. 전 리소스 `ap-northeast-2`(WAF Web ACL만 AWS 제약상 예외, §3.10). **NAT 없음 / Private Subnet 2개뿐**이라는 제약이 설계 전반을 지배한다.

### 0. 재검토 기록 (원본 PDF 재확인 + 실측)

최초 설계 이후 `task.pdf`(다이어그램 이미지 포함)와 `mark.sh`를 다시 원본에서 읽고, 핵심 가정 2건을 실측·재검증해 아래와 같이 정정했다.

1. **Lambda는 ALB가 아니라 CloudFront에서 직접 연결한다.** 문제지 1페이지 다이어그램을 실제로 렌더링해 확인한 결과, `Lambda` 아이콘은 `VPC` 박스 **밖**에 있고 화살표가 `CloudFront`에서 **직접** 내려와 `Lambda`로 들어간다(ALB·WAF 박스를 거치지 않음). 텍스트 근거도 있다 — "9. Load Balancing"이 명명한 Target Group은 `gj2026-book-tg`, `gj2026-grafana-tg` **딱 2개뿐**이며, Lambda용 3번째 Target Group 이름이 어디에도 없다. 이 과제는 리소스명을 전부 명시적으로 지정하는 방식이라, 이름이 없다는 것 자체가 "그 리소스가 없다"는 뜻이다. 최초 설계는 "Web ACL 1개로 CloudFront와 ALB를 동시에 커버할 수 없다"는 이유로 ALB Lambda 타깃그룹을 채택했는데, 이는 **WAF를 ALB(REGIONAL)에 붙인다는 전제 자체가 틀렸던 것** — WAF를 **CloudFront(CLOUDFRONT scope)에** 붙이면 Web ACL 1개가 엣지에서 `/v1/book`·`/reservation` 두 경로를 모두 검사하고, 그 뒤에 ALB든 Lambda Function URL이든 원하는 오리진으로 라우팅할 수 있다. §3.7·3.8·3.9·3.10 전면 수정.
2. **Gateway Endpoint는 1-2 채점을 깨지 않는다 — 오히려 DynamoDB엔 그것뿐이다.** 최초 설계는 "Gateway Endpoint가 라우트 테이블에 prefix-list 라우트를 추가해 `Routes[].DestinationCidrBlock` 출력에 `None`이 섞인다"고 판단해 전부 Interface Endpoint로 우회했다(S3까지 포함). 실제로 `jmespath` 라이브러리로 그 정확한 쿼리를 재현해보면, Gateway Endpoint 라우트는 `DestinationCidrBlock` 키 자체가 없고(`DestinationPrefixListId`만 있음) — JMESPath 프로젝션은 **결과가 null인 원소를 배열에서 아예 제외**하므로 `Routes[].DestinationCidrBlock`은 로컬 라우트 `10.0.0.0/16` 하나만 반환한다(실측: `jmespath.search(...)` → `['10.0.0.0/16']`, `None` 없음). 즉 Gateway Endpoint를 추가해도 1-2 출력은 그대로 정확히 일치한다. 이건 단순 최적화가 아니라 **필수 정정**이다 — DynamoDB는 애초에 Interface Endpoint 자체가 존재하지 않는 서비스(Gateway 전용)라, 이전 설계의 "dynamodb(interface)"는 AWS에 존재하지 않는 리소스를 만들려 한 것이었다. §3.1 전면 수정.

```
사용자 ──> CloudFront (gj2026-cdn, HTTP→HTTPS redirect)
   │       └ WAF Web ACL(CLOUDFRONT scope) gj2026-waf-acl 연결 — 모든 behavior 공통
   │           ├─ Rule1 deny-non-post-on-api      : /v1/book* AND method≠POST      → 405 Block
   │           └─ Rule2 deny-invalid-client-id    : /reservation* AND client_id 정규식 불일치 → 403 Block
   │
   ├─ Behavior[Default]        ──> S3 Origin(OAC) gj2026-static-<비번호>            [캐싱 O]
   │                                ├ CloudFront Function(viewer-request): 확장자 없는 URI → /index.html
   │                                └ SSE-KMS alias/gj2026-s3-key ← OAC에 Decrypt/GenerateDataKey 허용
   │
   ├─ Behavior[/v1/book*]  ┐
   ├─ Behavior[/grafana*]  ┘ VPC Origin(gj2026-alb-origin) [캐싱 X, 쿼리스트링 전달]
   │                          └─> ALB gj2026-alb (internal, private subnet a/b)
   │                                ├─ TG gj2026-book-tg(8080)    → EKS book Pod x2 (ns: skills)
   │                                │     ServiceAccount book-sa ─IRSA→ Role gj2026-book-app-role
   │                                │     (dynamodb:PutItem, kms:Decrypt → db-key)
   │                                └─ TG gj2026-grafana-tg(3000) → Grafana Pod (ns: monitoring)
   │                                      ServiceAccount ─IRSA→ Role gj2026-grafana-role
   │                                      (cloudwatch:GetMetricData/ListMetrics)
   │
   └─ Behavior[/reservation*]  ──> Lambda Function URL(OAC, AWS_IAM) gj2026-book-reservation
                                     IAM Role gj2026-lambda-role
                                     (dynamodb:Scan/Query, kms:Decrypt → db-key)

DynamoDB books (SSE-KMS alias/gj2026-db-key, GSI client_id-index)
   ← book-app-role : PutItem (IRSA, Gateway Endpoint 경유)
   ← lambda-role    : Scan/Query (VPC 밖, 퍼블릭 엔드포인트)
   ← 그 외 모든 주체: 리소스 기반 정책으로 쓰기 Deny (채점 3-3)

ECR(Private)
   ├─ book                      ← EKS app 노드 pull  (book Pod 이미지, zstd 압축)
   └─ ecr-public/nginx/nginx    ← EKS addon 노드 pull (pull-through cache, nginx-test Pod)

EKS Cluster gj2026-eks-cluster  — Secret 봉투 암호화 CMK alias/gj2026-eks-key

로그/메트릭 흐름
   book Pod(ns: skills) access log
     └─ Fluent Bit DaemonSet(ns: logging) ─IRSA→ Role gj2026-fluentbit-role(logs:PutLogEvents)
          └─ CloudWatch Logs /eks/book-svc/access (remote_addr 대역별 스트림 분리: -2a · -2b)
   Lambda gj2026-book-reservation
     └─ EMF 커스텀 메트릭(namespace gj2026/reservation, dim client_id) → CloudWatch Metrics
          └─ Grafana(ns: monitoring, 위 gj2026-grafana-role로 조회)
               └─ "WSI Dashboard" > Query Count Panel (ALL / C001 시리즈)
```

### 1. 요구사항 ↔ 채점항목 ↔ 리소스 매핑

| 채점 | 배점 | 구현 위치 | 핵심 판정 기준 |
|---|---|---|---|
| 1-1 VPC | 1.0 | `terraform/vpc.tf` | CIDR 10.0.0.0/16, 서브넷 **정확히 2개**(a=10.0.10.0/24, b=10.0.11.0/24) |
| 1-2 Route Table | 1.0 | `terraform/vpc.tf` | private-rtb-a/b의 `Routes[].DestinationCidrBlock`이 `10.0.0.0/16` 하나만(Gateway Endpoint 라우트는 이 필드가 없어 무관, §0-2) |
| 1-3 NAT Gateway | 1.0 | `terraform/vpc.tf` | 계정 내 NAT **0개**, IGW는 `gj2026-igw` 1개 |
| 2-1 ECR Repository | 1.0 | `terraform/ecr.tf` | repository name `book` |
| 2-2 ECR Image Size | 1.5 | `app/Dockerfile` + 런북 | `latest` 태그 이미지 `imageSizeInBytes` ≤ 3MB → **zstd 압축 필수** |
| 3-1 DynamoDB Config | 1.0 | `terraform/dynamodb.tf` | PK `booking_id`, GSI `client_id-index`(PK `client_id`) |
| 3-2 DynamoDB Encryption | 0.5 | `terraform/kms.tf` | SSE CMK가 `alias/gj2026-db-key` |
| 3-3 Access Restrictions | 1.0 | `terraform/dynamodb.tf` | 관리자 CloudShell `put-item`도 `AccessDeniedException` |
| 4-1 EKS Config | 1.0 | `eksctl/cluster.yaml` | 1.35 / ACTIVE / **public·private 엔드포인트 둘 다 True** / secret 암호화 CMK |
| 4-2 NodeGroup Config | 1.5 | `eksctl/cluster.yaml` | `BOTTLEROCKET_x86_64`, t3.medium×2 / m5.large×2 |
| 4-3 Node Naming | 1.5 | `eksctl/cluster.yaml` (bootstrap container) | 노드명 `gj2026.<instance_id>.(addon\|app).node` |
| 4-4 Application Pods | 1.0 | `k8s/app/` | `kubectl get deploy -n skills book` → 2/2 |
| 4-5 Network Policy | 1.5 | `k8s/app/securitygrouppolicy.yaml` + `terraform/vpc.tf`(Pod SG) | skills ns의 임의 Pod → `book-svc:8080` **타임아웃**, ALB는 정상 |
| 5-1 ALB Config | 1.0 | `terraform/alb.tf` | scheme `internal`, VPC = `gj2026-vpc` |
| 6-1 S3 Object | 1.0 | `terraform/s3.tf` | 루트에 `index.html`, `main.jpeg` (하위 디렉토리 금지) |
| 6-2 S3 Encryption | 1.0 | `terraform/s3.tf` | 기본 암호화 KMS = `alias/gj2026-s3-key` |
| 7-1 Lambda Config | 1.0 | `terraform/lambda.tf` | `gj2026-book-reservation` / `python3.14` / Active |
| 8-1 S3 Static Content | 1.0 | `terraform/cloudfront.tf` + Function | `/` Miss, `/main.jpeg` Miss, `/index.html` **Hit** |
| 8-2 ALB API | 1.5 | 전체 통합 | CF 경유 POST → `{"booking_id":"..."}` |
| 8-3 Lambda API 1 | 1.5 | `terraform/lambda.tf`(Function URL) + `lambda/index.py` | 전체 조회 JSON 배열 |
| 8-4 Lambda API 2 | 1.5 | 위와 동일 | `?client_id=C001` GSI 조회 |
| 9-1 HTTP Method | 1.5 | `terraform/waf.tf`(CLOUDFRONT scope) | `/v1/book` GET → `Method Not Allowed` + 405 |
| 9-2 Query String | 1.5 | `terraform/waf.tf`(CLOUDFRONT scope) | 잘못된 `client_id` → `Access Denied` + 403 |
| 10-1 Fluent Bit | 1.5 | `k8s/logging/` | AZ별 로그 스트림 2개, 메시지가 **JSON**이고 `remote_addr` 필드 존재 |
| 10-2 Grafana | 1.5 | `k8s/monitoring/` | `WSI Dashboard` / `Query Count Panel`에 `ALL`·`C001` 시리즈 |

### 2. 디렉토리 구조

```
set-06/task-1/
├── terraform/
│   ├── providers.tf      # provider 버전 고정, required_version
│   ├── variables.tf      # 기본값
│   ├── terraform.tfvars  # 비번호 등 세트 값 주입
│   ├── vpc.tf            # VPC·Subnet·IGW·RT·Gateway Endpoint(s3/dynamodb)·Interface Endpoint·SG
│   ├── kms.tf            # CMK 3종(db/s3/eks) + alias + 키 정책
│   ├── ecr.tf            # book repository + pull-through cache rule(ecr-public)
│   ├── dynamodb.tf       # 테이블·GSI·리소스 기반 정책
│   ├── alb.tf            # ALB·TG 2종(book/grafana)·Listener·Rule
│   ├── lambda.tf         # 함수·Function URL·OAC·권한
│   ├── lambda/index.py   # 조회 API + EMF 메트릭 (Function URL 이벤트 포맷)
│   ├── s3.tf             # 버킷·BPA·OAC 정책·정적 객체 업로드
│   ├── cloudfront.tf     # VPC Origin·Lambda OAC Origin·Distribution·Function·캐시 정책
│   ├── waf.tf            # Web ACL(CLOUDFRONT scope, us-east-1 provider) + custom response
│   ├── iam.tf            # IRSA 역할(book/lambda/fluent-bit/grafana/LBC)
│   └── outputs.tf        # CF 도메인·배포 ID·ECR URL·TG ARN·ENI IP 등
├── eksctl/
│   └── cluster.yaml      # 클러스터 + Bottlerocket 노드그룹 2개
├── k8s/
│   ├── 00-namespace.yaml
│   ├── app/              # configmap·deployment·service·securitygrouppolicy·targetgroupbinding
│   ├── monitoring/       # grafana values·dashboard configmap·targetgroupbinding
│   └── logging/          # fluent-bit values(파서·rewrite_tag)
├── app/Dockerfile        # scratch + 제공 바이너리 (zstd push)
├── plan.md · task.md · task.pdf · mark.md · mark.pdf · mark.sh
└── README.md             # 런북 (구현 시 작성)
```

제공 배포파일은 `shared/provided/set-06-task-1/` 에 원본 그대로 둔다(수정 금지).

### 3. 도메인별 설계

#### 3.1 VPC / Endpoint (vpc.tf)

- VPC `gj2026-vpc` 10.0.0.0/16, DNS hostnames·resolution 활성(엔드포인트 private DNS에 필수).
- Subnet **정확히 2개**: `gj2026-private-subnet-a`(10.0.10.0/24, 2a), `gj2026-private-subnet-b`(10.0.11.0/24, 2b). 채점 1-1이 VPC 내 전 서브넷을 나열하므로 **추가 서브넷을 만들면 즉시 오답**.
- Route Table `gj2026-private-rtb-a/b`: 라우트를 **하나도 추가하지 않는다**(local만 존재).
- IGW `gj2026-igw`를 VPC에 attach하되 **어떤 라우트 테이블에도 연결하지 않는다**. CloudFront VPC Origin 전제 조건일 뿐 인터넷 경로는 만들지 않는다.
- NAT Gateway 0개.
- **Gateway Endpoint(S3·DynamoDB)를 rtb-a/b에 정상적으로 붙인다.** §0-2에서 실측 확인했듯 Gateway Endpoint의 prefix-list 라우트는 `DestinationCidrBlock` 키가 없어 채점 1-2가 쓰는 JMESPath 프로젝션(`Routes[].DestinationCidrBlock`)에서 자동으로 빠진다 — 즉 1-2 출력은 여전히 `10.0.0.0/16` 하나만 나온다. DynamoDB는 애초에 **Gateway 타입만 존재**하고 Interface 옵션 자체가 없으므로(공식적으로 지원 안 함), book Pod가 DynamoDB에 접근하려면 이 방법이 유일하다. S3도 표준 관행대로 Gateway로 되돌린다(ECR 레이어가 S3에서 오므로).
- Interface Endpoint 목록(private DNS 활성, 두 서브넷 배치, SG는 VPC CIDR 443 허용):
  `ecr.api`, `ecr.dkr`, `logs`, `monitoring`, `sts`, `ec2`, `elasticloadbalancing`, `kms`, `eks`, `autoscaling`
  - `monitoring`은 Grafana CloudWatch 데이터소스가 사용.
- Gateway Endpoint 2개(`s3`, `dynamodb`)는 `route_table_ids = [rtb-a, rtb-b]`로 명시 연결한다(연결 안 하면 애초에 라우팅이 안 되어 접근 자체가 실패).
- SG 설계
  - `gj2026-alb-sg`: inbound 80 ← CloudFront VPC Origin (VPC Origin 사용 시 CloudFront가 관리하는 ENI에서 유입 → VPC CIDR 허용). outbound all.
  - `gj2026-endpoint-sg`: inbound 443 ← VPC CIDR.
  - 노드 SG는 eksctl/EKS 관리 SG + 필요한 추가 규칙만.

#### 3.2 KMS (kms.tf)

CMK 3개 + alias. 채점이 alias 이름으로 역추적하므로 alias 정확성이 곧 점수.

| alias | 용도 | 키 정책 추가 사항 |
|---|---|---|
| `alias/gj2026-db-key` | DynamoDB SSE | book/Lambda 역할에 Decrypt·GenerateDataKey |
| `alias/gj2026-s3-key` | S3 기본 암호화 | **CloudFront OAC(`cloudfront.amazonaws.com`)에 Decrypt·GenerateDataKey**, `AWS:SourceArn`=배포 ARN 조건 |
| `alias/gj2026-eks-key` | EKS Secret 봉투 암호화 | EKS 서비스 사용 허용(기본 root 위임으로 충분) |

S3 CMK에 CloudFront 권한을 빠뜨리면 8-1이 전부 실패한다(SSE-KMS 객체를 OAC가 못 읽음).

#### 3.3 ECR + 컨테이너 이미지 (ecr.tf, app/Dockerfile)

- Repository `book`. 이미지 태그는 **`latest`** (채점 2-2가 `imageTags[0]==latest` 로 필터).
- **Pull-through cache rule 필수**: prefix `ecr-public` → upstream `public.ecr.aws`.
  채점 4-5가 `${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/nginx/nginx:latest` 를 pull 한다. 룰이 없으면 nginx-test Pod가 뜨지 않아 1.5점을 잃는다. 문제지 5번의 "추가 외부 이미지는 Private ECR로 제공" 요구와 같은 항목.
  - ECR 문서상 **PTC 최초 pull에는 인터넷 경로가 필요할 수 있다**. 채점 순서상 CloudShell(인터넷 O)의 `docker pull`이 먼저 실행되어 캐시를 채우므로 노드 pull은 캐시 히트가 되지만, **우리가 쓰는 이미지(LBC·Grafana·bootstrap container)는 PTC에 의존하지 말고 로컬에서 private ECR로 직접 push** 한다. 노드 부팅·핵심 워크로드 경로에 PTC를 두지 않는다.
  - 사전 검증: 배포 후 직접 `docker pull .../ecr-public/nginx/nginx:latest` 를 한 번 돌려 캐시를 미리 채워둔다.
- 이미지 크기 제약이 이 과제 최대 난관:

| 압축 | 결과 | 판정 |
|---|---|---|
| 원본 바이너리 | 8.36 MiB | — |
| gzip -9 (docker 기본) | **3.32 MiB** | 초과 → 탈락 |
| xz -9 | 2.53 MiB | (OCI 미지원) |
| **zstd -19** | **2.75 MiB** | 통과 |

  제공자료 수정 금지이므로 UPX·strip 등 바이너리 가공은 불가. **레이어 압축 알고리즘을 zstd로 바꾸는 것이 유일한 합법 경로**.

```dockerfile
FROM scratch
COPY book-linux-amd64_v1.0.1 /book
EXPOSE 8080
ENTRYPOINT ["/book"]
```

  정적 링크 바이너리이므로 base 이미지가 필요 없다(레이어 1개 = 바이너리뿐 → 압축 크기 최소).

```bash
docker buildx build --platform linux/amd64 --provenance=false \
  --output type=image,name=$ECR:latest,oci-mediatypes=true,compression=zstd,compression-level=19,force-compression=true,push=true \
  -f app/Dockerfile ../../shared/provided/set-06-task-1
```

- **`oci-mediatypes=true` 누락 금지**: 없으면 Docker 계열 zstd media type(`vnd.docker.image.rootfs.diff.tar.zstd`)으로 나갈 수 있는데 containerd가 이를 지원하지 않는다. OCI 타입(`application/vnd.oci.image.layer.v1.tar+zstd`)이어야 한다.
- `force-compression=true` 없으면 캐시된 gzip 레이어를 그대로 재사용해 zstd 변환이 일어나지 않는다.
- `--platform linux/amd64` 단일 아키텍처로 빌드한다. manifest list가 되면 `imageSizeInBytes`가 "모든 매니페스트 중 최대값"이 되어 의도와 다른 값이 나온다.
- ECR의 `imageSizeInBytes`는 **압축(푸시) 크기**이므로 zstd 이득이 그대로 반영된다.
- Bottlerocket `aws-k8s-1.35` variant는 containerd 2.1이라 OCI zstd를 완전히 지원한다(containerd 1.5+부터 기본 지원).
- **주의: zstd 이미지는 Docker Engine으로 `docker run` 검증이 불가능하다.** 로컬에서는 크기만 확인하고, 실제 구동 검증은 클러스터 배포로만 가능하다 → 경기 당일 처음 돌리지 말고 사전에 1회 배포 검증한다.

#### 3.4 DynamoDB (dynamodb.tf)

- 테이블 `books`, PAY_PER_REQUEST, hash_key `booking_id`(S).
- GSI `client_id-index`, hash_key `client_id`(S), projection **INCLUDE**(`username`,`email`,`concert_name`) 또는 ALL — 8-4 응답 필드를 GSI만으로 만들 수 있어야 조회가 1회로 끝난다.
- `attribute` 정의는 `booking_id`, `client_id` **두 개만**(키로 쓰이는 속성만 정의 가능).
- SSE: `kms_key_arn = alias/gj2026-db-key` 대상 CMK.
- **리소스 기반 정책(3-3 핵심)**: 쓰기 액션을 book 앱 역할 외 전원에게 Deny.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyWritesExceptBookApp",
    "Effect": "Deny",
    "Principal": "*",
    "Action": ["dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:DeleteItem","dynamodb:BatchWriteItem"],
    "Resource": "arn:aws:dynamodb:ap-northeast-2:<ACCOUNT_ID>:table/books",
    "Condition": {"StringNotLike": {"aws:PrincipalArn": [
      "arn:aws:iam::<ACCOUNT_ID>:role/gj2026-book-app-role",
      "arn:aws:sts::<ACCOUNT_ID>:assumed-role/gj2026-book-app-role/*"
    ]}}
  }]
}
```

  - 테이블 자체(Create/Delete/Describe/Scan/Query)는 막지 않는다 → Terraform 관리와 Lambda 조회에 영향 없음.
  - **함정**: 이 Deny가 걸리면 관리자도 아이템을 지울 수 없다. "채점 전 데이터 항목 0개" 요구를 위해 변수 `enable_ddb_write_deny`(기본 true)를 두고, 정리 시 `false`로 apply → 아이템 삭제 → 다시 `true`로 apply 하는 절차를 런북에 넣는다.

#### 3.5 EKS (eksctl/cluster.yaml)

- 클러스터 `gj2026-eks-cluster`, 버전 `1.35`, 기존 VPC/서브넷 사용(`vpc.id`, `vpc.subnets.private`).
- `clusterEndpoints: {publicAccess: true, privateAccess: true}` — 채점 4-1이 `True True` 를 요구. CloudShell에서 kubectl이 동작해야 하므로 public도 필수.
- `secretsEncryption.keyARN` = `alias/gj2026-eks-key` 대상 CMK (4-1 두 번째 줄).
- NodeGroup 2개 모두 `amiFamily: Bottlerocket`, `privateNetworking: true`, desiredCapacity 2.

| 노드그룹 | 인스턴스 | 라벨 | Taint | EC2 Name 태그 |
|---|---|---|---|---|
| `gj2026-eks-addon-nodegroup` | t3.medium ×2 | `role=addon` | 없음 | `gj2026-eks-addon-node` |
| `gj2026-eks-app-nodegroup` | m5.large ×2 | `role=app` | `dedicated=app:NoSchedule` | `gj2026-eks-app-node` |

- **`ami:` 필드를 지정하면 안 된다.** 커스텀 AMI를 지정하는 순간 `describe-nodegroup`의 amiType이 `CUSTOM`으로 바뀌어 채점 4-2가 깨진다. `amiFamily: Bottlerocket`만 쓰고 AMI 선택은 EKS에 맡긴다.
- **Addon 배치**: Deployment형 애드온(CoreDNS, metrics-server)은 addon의 `configurationValues`로 `nodeSelector` 지정. DaemonSet형(vpc-cni, kube-proxy)은 전 노드에 도는 것이 정상. 스키마는 애드온·버전마다 다르므로 `aws eks describe-addon-configuration --addon-name coredns --addon-version <v> --query configurationSchema` 로 **먼저 확인**하고, 반영은 `--resolve-conflicts OVERWRITE`로 해야 한다(없으면 무시됨).

```json
{ "nodeSelector": { "role": "addon" },
  "tolerations": [] }
```

- app 노드에는 book Pod 외 아무것도 두지 않는다(요구 7). app 노드그룹에만 taint(`dedicated=app:NoSchedule`)를 걸고, addon 노드그룹은 taint 없이 nodeSelector로만 유도한다. addon 노드에 taint를 걸면 광역 toleration이 없는 컴포넌트(metrics-server 등)가 Pending에 빠진다.

##### 3.5.1 노드 이름 커스터마이징 (채점 4-3, 1.5점)

- Bottlerocket에는 셸이 없어 `preBootstrapCommands`가 성립하지 않고, eksctl 공식 문서도 **Bottlerocket에서 `overrideBootstrapCommand` 미지원**을 명시한다. managed nodegroup + launch template 조합에서도 두 필드 모두 unsupported.
- `settings.kubernetes.hostname-override-source`는 `private-dns-name` / `instance-id` 두 값만 지원 → 노드명이 `i-0abc...` 형태로만 나오므로 요구 포맷 불가.
- 유일한 경로는 **bootstrap container**. Bottlerocket 공식 문서 기준 bootstrap container는 *kubelet보다 먼저 실행되고, 모두 종료될 때까지 systemd가 다음 target으로 넘어가지 않는다.* 즉 kubelet이 뜨기 전에 `hostname-override`를 심을 수 있다.

```yaml
managedNodeGroups:
  - name: gj2026-eks-addon-nodegroup
    amiFamily: Bottlerocket
    instanceType: t3.medium
    desiredCapacity: 0   # 인증 전환 전 부팅 방지 — 전환 후 scale-up (§3.5.2 채택 전략)
    minSize: 0
    maxSize: 2
    privateNetworking: true
    labels: { role: addon }
    bottlerocket:
      settings:
        bootstrap-containers:
          set-hostname:
            source: <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/gj2026/br-bootstrap:1.0.0
            mode: once        # 1회 실행 후 자동 off
            essential: true   # 실패 시 부팅 중단 → 잘못된 이름의 노드가 조인하지 않음
            user-data: <base64(아래 스크립트)>
```

```sh
#!/usr/bin/env bash
set -euo pipefail
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 600")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

apiclient set --json "{\"settings\":{\"kubernetes\":{
  \"hostname-override\":\"gj2026.${IID}.addon.node\",
  \"provider-id\":\"aws:///${AZ}/${IID}\"}}}"
```

- **`provider-id`를 반드시 함께 설정한다.** EKS 1.35는 external cloud provider를 쓰기 때문에, 노드 이름이 private DNS name이 아니면 cloud controller manager가 노드↔EC2 매칭에 실패해 `node.cloudprovider.kubernetes.io/uninitialized` taint가 벗겨지지 않고 NotReady에 머물 수 있다. **이 조합은 문서만으로 100% 확정되지 않았으므로 클러스터에서 1회 실측 검증이 필수**(최우선 리스크).
- bootstrap container 이미지는 `public.ecr.aws/bottlerocket/bottlerocket-bootstrap` 기반으로 **로컬에서 private ECR로 직접 push**한다. ECR pull-through cache는 최초 pull 시 인터넷 경로가 필요할 수 있어 노드 부팅 경로에 두면 위험하다. 이 이미지는 kubelet이 아니라 호스트의 `host-ctr`가 인스턴스 프로파일 권한으로 당기므로 노드 IAM에 ECR read 권한이 있어야 한다.
- 검증: `kubectl get nodes` 로 4개 노드가 `gj2026.i-xxxx.addon.node` / `...app.node` 로 뜨는지, `aws eks list-access-entries` 로 노드 role access entry가 생성됐는지 확인.

##### 3.5.2 실측 기록 (2026-07-22): NodeCreationFailure 2회 재현 — hostname-override 가 유력 원인

**증상**: 두 managed 노드그룹 모두 `NodeCreationFailure(Instances failed to join)`. 콘솔 로그상 부팅·bootstrap container·kubelet 기동까지 전부 정상. 서로 다른 날 2회 동일 재현(인스턴스 ID만 다름). 노드그룹별 차이 요소(SG, taint, 인스턴스 타입)는 원인에서 배제 — 공통 요소가 원인.

**유력 메커니즘** (문서 근거, 실측 미확정 — 카나리로 확정할 것):
- managed 노드그룹은 노드 role 에 `EC2_LINUX` 타입 access entry 를 자동 생성하며, username 템플릿이 `system:node:{{EC2PrivateDNSName}}` 으로 **고정**된다(API_AND_CONFIG_MAP 모드에서 access entry 가 configmap 보다 우선 → 우회 불가).
- kubelet 이 `gj2026.i-xxx.app.node` 로 Node 객체 생성 시도 → username(`system:node:ip-10-...`)과 불일치 → Node authorizer 거부, RBAC 폴백도 바인딩 없음 → Forbidden → 등록 실패 → EKS 가 ASG 를 0으로 강제 스케일다운(CFN rollback 설정과 무관하게 인스턴스 삭제).
- 같은 메커니즘의 공개 사례: bottlerocket-os/bottlerocket#3028 (custom domain-name → 노드명 불일치 → lease Forbidden → join 실패). 수정 방향도 "노드명을 private DNS name 으로 고정"이었음 — EKS 에서 노드명 ≠ private DNS name 은 기본 경로로는 성립하지 않는다.

**확정 (2026-07-23)**: 카나리(bootstrap 블록 제거 managed NG)가 정상 join·Ready — 네트워킹 정상, hostname-override 가 원인으로 실측 확정.

**폐기된 우회안 — 유령 노드**: 정규 NG 는 기본 노드명으로 두고, 채점 4-3 전용 Bottlerocket EC2 4대를
STANDARD access entry(`gj2026:node`) + ClusterRoleBinding(system:node)으로 등록만 시키는 방식.
등록 자체는 실측 성공했으나 폐기 — 이유: (1) 출제 의도(task.md "cluster에 등록되는 노드 이름을 변경")는
실노드 개명이지 노드 추가가 아님, (2) `kubectl get nodes` 에 8대가 보여 수동 재채점·"정확히 일치" 해석에 취약,
(3) NodeRestriction 우회하는 통짜 `system:node` RBAC 바인딩(보안 감점 여지), (4) EC2 4대 비용·관리 추가.

**채택 전략 — 정규 노드 개명 (aws-auth `{{SessionName}}` 매핑)**:
join 거부의 원인은 hostname-override 자체가 아니라 **인증 매핑**이다 — managed NG 가 자동 생성하는
`EC2_LINUX` access entry 의 username 템플릿(`system:node:{{EC2PrivateDNSName}}`)이 고정이라
커스텀 노드명과 불일치했을 뿐. 매핑을 aws-auth ConfigMap 경로로 전환하면 정규 노드가 4-2·4-3 을 동시에 충족한다:
- 클러스터 `accessConfig.authenticationMode: API_AND_CONFIG_MAP` 명시 — access entry 가 **없는** principal 은 aws-auth 로 폴백된다.
- NG 는 §3.5.1 그대로 bootstrap container(hostname-override + provider-id) 포함, 단 **desired/min 0 으로 생성**.
  (desired 2 로 생성하면 인증 전환 전에 노드가 부팅 → join 실패 → NodeCreationFailure 롤백, 실측 §3.5.2 재발)
- NG 생성 후: 자동 생성된 EC2_LINUX access entry 2개 **삭제** → `eksctl create iamidentitymapping` 으로
  aws-auth 에 `username: system:node:gj2026.{{SessionName}}.<role>.node` 매핑(groups: system:bootstrappers, system:nodes).
  EC2 인스턴스 프로파일 세션의 `{{SessionName}}` = **instance-id** 이므로 username 이 노드명과 정확히 일치 →
  Node authorizer·NodeRestriction 정상 경로 유지(RBAC 구멍 없음).
- 이후 `eksctl scale nodegroup --nodes 2 --nodes-min 2` — 4-2 의 desiredSize 2 는 scale 후 충족.
  scale-up 단계 join 실패는 NG 를 롤백시키지 않으므로(생성 실패와 달리) 재시도 여지가 있다.
- **주의(실측)**: eksctl 은 MNG 생성 시 aws-auth 에 기본 매핑(`system:node:{{EC2PrivateDNSName}}`)을 직접
  추가한다 — access entry 삭제만으로는 부족하고, 커스텀 매핑 생성 전에
  `eksctl delete iamidentitymapping --arn <role> --all` 로 기본 매핑을 제거해야 중복 순서 문제를 피한다.
  클러스터 생성자 관리자 권한은 access entry(bootstrapClusterCreatorAdminPermissions 기본 true)로 유지 — CloudShell 채점 영향 없음.

**실측 결과 (2026-07-23, 전 항목 확정)**:
1. ✅ scale-up·인스턴스 교체 시 EC2_LINUX access entry **재생성 안 됨** (CreateNodegroup 시점에만 생성).
2. ✅ 노드 4대 `gj2026.i-xxxx.(addon|app).node` 로 join·Ready. mark.sh 4-2/4-3 로직 그대로 재현해 기대 출력과 정확히 일치.
   MNG 는 `DEGRADED (AccessDenied: AccessEntry isn't found)` 로 표기되지만 노드 동작·4-2 채점 필드에 무영향, 노드 강제 교체도 없음.
3. ⚠️ **kubelet-serving CSR 이 Pending 으로 남는다** — EKS CSR 자동 승인기가 커스텀 노드명을 승인하지 않음.
   방치 시 kubelet 서빙 인증서 부재로 `kubectl logs/exec` 전멸 → metrics-server NotReady + **채점 4-5(nginx-test exec) 실패**.
   조치: 노드 Ready 후 `kubectl get csr -o name | xargs -n1 kubectl certificate approve` 1회(노드 교체 시 재실행). 승인 후 `kubectl top nodes`·logs·exec 정상 확인.
4. 기타: bootstrap container 는 `essential=true` 라 이미지 미존재 시 부팅이 멈춘다(콘솔 로그 `Failed to start bootstrap container`).
   br-bootstrap push(런북 4단계)가 반드시 선행돼야 하며, 실패한 인스턴스는 종료하면 ASG 가 새로 띄워 정상 join 한다.

#### 3.6 애플리케이션 (k8s/app/)

- Namespace `skills`.
- ConfigMap: `AWS_REGION=ap-northeast-2`, `TABLE_NAME=books`.
- Deployment `book`, replicas 2, image `<ECR>/book:latest`, containerPort 8080,
  `tolerations: dedicated=app:NoSchedule`, `nodeSelector: role=app`,
  `topologySpreadConstraints`로 AZ 분산(고가용성 + 10-1의 AZ별 로그 스트림 2개 확보에 직결).
  ServiceAccount `book-sa`(IRSA → `gj2026-book-app-role`).
- Service `book-svc` ClusterIP 8080 → 8080.
- ALB 연결은 **TargetGroupBinding**(AWS Load Balancer Controller) — TG는 Terraform이 만들고 k8s가 바인딩만 한다. LBC는 addon 노드에 배치.
- **Pod 격리(4-5)**: 구현안은 §3.6.1.
- **Probe를 달지 않는다.** 아래 SGP strict 모드에서 kubelet probe를 통과시키려면 노드 SG를 8080에 열어야 하는데, 그러면 같은 노드의 nginx-test도 통과해 4-5가 깨진다. 헬스체크는 ALB 타깃 그룹이 수행하므로 liveness/readiness probe 없이도 4-4(2/2 READY)와 8-2가 모두 성립한다.

##### 3.6.1 "ALB에서 오는 요청만 수신" 구현 (채점 4-5, 1.5점)

Pod IP와 ALB ENI IP가 **같은 서브넷 CIDR**을 공유하므로 CIDR 기반 구분이 원천적으로 불가능하다. 두 가지 안을 비교한 결과 **SecurityGroupPolicy(SGP)** 를 채택한다.

| | (a) VPC CNI NetworkPolicy | (b) SecurityGroupPolicy ← 채택 |
|---|---|---|
| ALB 식별 | ALB ENI IP를 `/32`로 나열 | **ALB SG를 source로 참조** |
| 안정성 | ALB 스케일 시 ENI/IP 변경 → 구조적으로 깨짐 | ALB가 스케일해도 유효 |
| 제약 | vpc-cni ≥1.21.0 + `enableNetworkPolicy` 필요, Deployment 소속 Pod에만 적용 | trunk ENI 지원 인스턴스 필요 |
| 이번 과제 적용성 | 가능하나 불안정 | book Pod는 **m5.large(app 노드)** → 지원 |

**t3.medium은 trunk ENI를 지원하지 않는다**(`IsTrunkingCompatible: false`, t 패밀리 전체 미지원). 다행히 SGP가 필요한 것은 app 노드그룹(m5.large)의 book Pod뿐이므로 문제되지 않는다. addon 노드에는 SGP를 쓰지 않는다.

```bash
kubectl set env daemonset aws-node -n kube-system ENABLE_POD_ENI=true
```

```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata: { name: book-sgp, namespace: skills }
spec:
  podSelector:
    matchLabels: { app: book }
  securityGroups:
    groupIds: [ <gj2026-book-pod-sg> ]
```

Pod SG (`gj2026-book-pod-sg`) 규칙 — Terraform에서 생성:

| 방향 | 포트 | 상대 | 이유 |
|---|---|---|---|
| ingress | 8080 | **ALB SG 참조** | ALB만 통과. nginx-test는 노드 primary ENI를 소스로 오므로 자동 차단 |
| egress | 443 | endpoint SG | STS·Logs 등 Interface 엔드포인트 |
| egress | 443 | **DynamoDB prefix list**(`data.aws_prefix_list` service=dynamodb) | Gateway Endpoint는 ENI가 없어 SG가 아니라 **prefix-list 대상 egress 규칙**이 필요하다 |
| egress | 53 (TCP/UDP) | 노드 SG / VPC CIDR | CoreDNS 조회 |

- `POD_SECURITY_GROUP_ENFORCING_MODE`는 **기본값 strict 유지** — branch ENI SG만 평가되어 "Pod 트래픽을 노드 트래픽에서 완전히 분리"한다는 AWS 문서상의 용도와 정확히 일치한다.
- strict 모드는 source NAT를 끄지만, 이 과제는 NAT 자체가 없고 모든 외부 통신이 VPC 엔드포인트 경유라 영향이 없다. 단 **DynamoDB prefix-list egress를 빠뜨리면 앱이 DynamoDB에 못 붙는다**(Gateway Endpoint는 SG가 없어 "endpoint SG" 참조로는 안 열린다 — 놓치기 쉬움).
- `terminationGracePeriodSeconds`를 0으로 두지 않는다(branch ENI 정리 실패).
- SG를 1개만 붙이므로 LBC의 backend SG 규칙 자동 관리와 충돌하지 않는다. TargetGroupBinding 사용 시에도 Pod SG를 직접 관리하는 편이 예측 가능하다.
- **Fallback**: SGP가 동작하지 않으면 vpc-cni addon에 `{"enableNetworkPolicy":"true"}` 를 주고 ALB ENI IP `/32` 나열 NetworkPolicy로 전환(경기 당일 한정 임시 통과용).

#### 3.7 ALB (alb.tf)

- `gj2026-alb`, **internal**, private subnet a/b, HTTP:80 리스너.
- Target Group **2종**(task.md 9번 항목이 이름을 딱 2개만 명시 — Lambda용 3번째 TG는 없다, §0-1):
  - `gj2026-book-tg`: type ip, 8080, health check `/health`
  - `gj2026-grafana-tg`: type ip, 3000, health check `/grafana/api/health`
- 리스너 규칙: `/v1/book*`→book, `/grafana*`→grafana, default fixed-response 404.
- WAF는 이 ALB에 붙이지 않는다 — CloudFront 엣지에 붙인다(§3.10).

Lambda는 **ALB 타깃그룹이 아니라 Function URL로 CloudFront에 직접 연결**한다(§3.8). 최초 설계는 "Web ACL 1개로 CloudFront·ALB를 동시에 커버할 수 없다"는 이유로 ALB 경유를 택했지만, 이는 WAF를 REGIONAL/ALB에 붙인다는 전제 자체가 원본 다이어그램·리소스명 목록과 맞지 않았다(§0-1). WAF를 CloudFront(CLOUDFRONT scope)에 붙이면 하나의 Web ACL이 엣지에서 모든 경로를 검사한 뒤 ALB든 Lambda든 원하는 오리진으로 보낼 수 있어, 굳이 Lambda를 ALB 뒤에 둘 필요가 없다.

#### 3.8 Lambda (lambda.tf, lambda/index.py)

- `gj2026-book-reservation`, runtime `python3.14`, VPC 밖(엔드포인트 불필요 — VPC 설정을 하지 않은 Lambda는 AWS 백본을 통해 DynamoDB 퍼블릭 엔드포인트에 바로 접근하므로, book Pod와 달리 VPC Endpoint가 필요 없다. 다이어그램에서도 Lambda 아이콘이 VPC 박스 밖에 있는 것과 일치, §0-1).
- **Function URL**로 CloudFront에 직접 연결한다(ALB 타깃그룹 아님, §3.7). `auth_type = "AWS_IAM"`(NONE이면 안 됨 — OAC 서명 검증이 IAM 인증 경로를 전제로 함).
- Function URL 페이로드는 **API Gateway v2.0 포맷 고정**이다. ALB 타깃과 필드명이 다르므로 주의:

```python
def handler(event, context):
    qs = event.get("queryStringParameters") or {}   # dict, 단일값 (ALB의 multiValue와 다름)
    client_id = qs.get("client_id")
    ...
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(items),
    }
```

  `event['rawPath']`, `event['requestContext']['http']['method']` 등도 사용 가능하나 이 함수는 경로 분기가 없어 불필요. `statusCode` 누락 시 502.
- **CloudFront OAC(Lambda 오리진 타입)**: `aws_cloudfront_origin_access_control`에 `origin_access_control_origin_type = "lambda"`. Lambda 리소스 정책에 `lambda:InvokeFunctionUrl`를 `cloudfront.amazonaws.com`에 허용하고 `AWS:SourceArn`=배포 ARN 조건을 건다.

```hcl
resource "aws_lambda_permission" "cf_oac" {
  statement_id  = "AllowCloudFrontOAC"
  action        = "lambda:InvokeFunctionUrl"
  function_name = aws_lambda_function.reservation.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.main.arn
}
```

- `python3.14`는 정식 지원 런타임(deprecation 2029-06-30).
- 로직
  - `client_id` 없음 → `Scan`(ProjectionExpression username,email,concert_name) → 배열 반환, 메트릭 차원 `ALL`
  - `client_id` 있음 → GSI `client_id-index` `Query` → 배열 반환, 메트릭 차원 그 값(`C001`)
  - `json.dumps` 기본 구분자(`, ` / `: `)가 채점 예상 출력과 동일하므로 별도 포맷 지정 금지.
- **메트릭(10-2)**: EMF(Embedded Metric Format)로 stdout에 JSON 출력 → CloudWatch가 자동 집계. 네임스페이스 `gj2026/reservation`, 메트릭 `QueryCount`, 차원 `client_id`.
  채점 이미지상 `ALL`과 `C001`이 **각각 1개**씩 찍히므로 `ALL`은 전체 합계가 아니라 **client_id 미지정 조회의 차원 값**이다(합계라면 8-3+8-4=2가 되어야 함).
  - EMF는 `logs:PutLogEvents` 권한만으로 동작한다(`cloudwatch:PutMetricData` 불필요, API 호출 0회).
  - **`logging` 모듈을 쓰면 안 된다.** `[INFO] <ts> <reqid>` 접두어가 붙어 EMF 파싱이 깨진다. **`print(json.dumps(...))`만** 사용.
  - `Dimensions`는 배열의 배열이며 `[["client_id"]]` **하나만** 넣는다. 빈 DimensionSet을 추가하면 Grafana의 `client_id=*` 조회에 잡히지 않으면서 과금만 는다.

```python
import json, time

def emit_query_count(client_id):
    print(json.dumps({
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": "gj2026/reservation",
                "Dimensions": [["client_id"]],
                "Metrics": [{"Name": "QueryCount", "Unit": "Count"}],
            }],
        },
        "client_id": client_id,    # 차원 값은 최상위 필드
        "QueryCount": 1,
    }))

emit_query_count(client_id or "ALL")   # 미지정 조회는 "ALL"
```
- IAM: `dynamodb:Scan`,`dynamodb:Query`(테이블+인덱스), `kms:Decrypt`, 기본 로그 권한.

#### 3.9 S3 + CloudFront (s3.tf, cloudfront.tf)

- 버킷 `gj2026-static-<비번호>`(변수 `bibunho`), Public Access Block 4옵션 true.
- 기본 암호화 SSE-KMS = `alias/gj2026-s3-key`, `bucket_key_enabled = true`.
- 객체는 **루트에** `index.html`(`text/html`), `main.jpeg`(`image/jpeg`) 업로드. 채점 6-1이 `/`를 포함하지 않는 키만 나열하므로 접두사 디렉토리 금지.
- Distribution `gj2026-cdn`(Name 태그 포함), 기본 인증서, HTTP→HTTPS `redirect-to-https`.
- **`web_acl_id`에 CLOUDFRONT scope Web ACL(§3.10)의 ARN을 직접 지정** — REGIONAL과 달리 별도 association 리소스가 없다.
- Origin 3개
  - S3 origin: OAC(sigv4, always)
  - **VPC Origin `gj2026-alb-origin`**: `aws_cloudfront_vpc_origin`으로 internal ALB 연결, HTTP only 80
  - **Lambda Function URL origin**: OAC(origin type `lambda`), HTTPS only, `custom_origin_config`(§3.8)
- Behavior (전 behavior `viewer_protocol_policy = redirect-to-https`)
  | 경로 | Origin | 캐시 정책 | 오리진 요청 정책 | 비고 |
  |---|---|---|---|---|
  | Default | S3 | `CachingOptimized` `658327ea-f89d-4fab-a63d-7e88639e58f6` | — | **viewer-request Function은 여기에만** |
  | `/v1/book*` | ALB(VPC Origin) | `CachingDisabled` `4135ea2d-6df8-44a3-9df3-4b5a84be39ad` | `AllViewerExceptHostHeader` `b689b0a8-53d0-40ab-baf2-68738e2966ac` | 전 메서드(POST) |
  | `/grafana*` | ALB(VPC Origin) | 동일 | 동일 | 전 메서드(로그인 POST) |
  | `/reservation*` | **Lambda Function URL** | 동일 | 동일 | 쿼리스트링 전달 |

  **`AllViewerExceptHostHeader`가 쿼리스트링을 전부 오리진에 전달한다. 빠뜨리면 WAF가 `client_id`를 보지 못해 9-2가 통째로 실패한다.**

```hcl
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "gj2026-alb-origin"
    arn                    = aws_lb.main.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols { items = ["TLSv1.2"]  quantity = 1 }
  }
}
```

  VPC Origin은 ap-northeast-2 지원, IGW는 VPC에 attach만 하면 되고 **라우트 추가는 불필요**하다(1-2 안전). 생성에 최대 15분.

- S3 CMK 키 정책에 아래가 없으면 8-1이 전부 실패한다.

```json
{ "Sid": "AllowCloudFrontOAC", "Effect": "Allow",
  "Principal": {"Service": "cloudfront.amazonaws.com"},
  "Action": ["kms:Decrypt", "kms:GenerateDataKey*"], "Resource": "*",
  "Condition": {"StringEquals": {
    "AWS:SourceArn": "arn:aws:cloudfront::<ACCOUNT_ID>:distribution/<DIST_ID>"}} }
```
- **CloudFront Function (viewer-request, 기본 behavior에만 연결)**

```js
function handler(event) {
  var req = event.request;
  var uri = req.uri;
  if (uri.endsWith('/')) { req.uri = uri + 'index.html'; }
  else if (!uri.split('/').pop().includes('.')) { req.uri = '/index.html'; }
  return req;
}
```

  viewer-request 함수는 **캐시 조회 전에** 실행되고 반환된 요청의 URI가 캐시 키가 된다(공식 문서 확인). 따라서 `/` → `/index.html` 재작성으로 캐시 키가 통일되어 8-1의 세 번째 요청이 Hit가 된다. `default_root_object` 단독으로 캐시 키가 합쳐진다는 근거는 없다.
  반면 **behavior·오리진 선택은 원본 URI 기준**이다("it doesn't change the cache behavior for the request or the origin"). 그래서 함수를 기본 behavior에만 붙여도 API 경로는 안전하다 — 반대로 ALB behavior에 붙이면 확장자 없는 `/reservation`이 `/reservation/index.html`로 재작성되어 Lambda가 깨진다.

#### 3.10 WAF (waf.tf)

**`scope = "CLOUDFRONT"`**, CloudFront 배포(`gj2026-cdn`)에 직접 연결(`web_acl_id` 속성, §3.9). 기본 동작 Allow.

- **CLOUDFRONT scope Web ACL은 반드시 `us-east-1`에서 생성해야 하는 AWS API 제약**이다 — CloudFront 자체가 리전이 없는 글로벌 리소스인 것과 같은 종류의 예외이며, ACM에서 CloudFront용 인증서를 반드시 us-east-1에 만드는 것과 동일한 패턴이다. `provider "aws" { alias = "us_east_1"  region = "us-east-1" }`를 만들고 `aws_wafv2_web_acl`에 `provider = aws.us_east_1`를 지정한다. "전 리소스 서울 리전" 원칙의 유일한 예외로 문서화해둔다.
- 엣지에서 evaluate되므로 ALB(내부 오리진)나 Lambda Function URL 앞에 별도 REGIONAL Web ACL을 추가할 필요가 없다 — Web ACL 1개로 `/v1/book`·`/reservation` 두 경로 모두 커버(§0-1).

| 우선순위 | 규칙 | 조건 | 동작 |
|---|---|---|---|
| 1 | `deny-non-post-on-api` | URI가 `/v1/book`로 시작 **AND** method ≠ POST | Block, 405, body `Method Not Allowed` |
| 2 | `deny-invalid-client-id` | URI가 `/reservation`로 시작 **AND** 쿼리에 `client_id=` **존재** **AND** 정규식 불일치 | Block, 403, body `Access Denied` |

- **method 규칙은 반드시 `/v1/book`로 스코프를 좁힌다.** ALB 전체에 걸면 Grafana GET(10-2)과 `/reservation` GET(8-3/8-4)이 함께 차단되어 4.5점이 날아간다. 이때 `scope_down_statement`는 managed rule group / rate-based 전용이므로 **`and_statement`** 로 조합해야 한다.
- **정규식에 앵커(`^...$`)를 반드시 붙인다.** WAF 정규식은 PCRE **부분 매칭**이라 앵커가 없으면 `홍길동`의 URL 인코딩 `%ED%99%8D%EA%B8%B8%EB%8F%99` 안의 `B8`(문자+숫자)에 매칭되어 **통과해 버린다**.

```
^[A-Za-z][A-Za-z0-9]*[0-9][A-Za-z0-9]*$
```

  `C001` 통과 / `123abc`(숫자 시작)·`C^001`(특수문자)·`홍길동`(비ASCII) 차단. `\d` 대신 `[0-9]`를 쓴다(AWS가 지원 construct 전체를 공개하지 않음). 텍스트 변환은 URL_DECODE.
- **"존재" 검사를 빼면 1.5점을 잃는다.** WAF는 지정한 요청 컴포넌트가 아예 없으면 "매칭되지 않음"으로 평가하므로, `NOT(regex)` 단독이면 `client_id`가 **없는** 요청(8-3의 `curl /reservation`, 200이어야 함)까지 차단된다. `query_string` **CONTAINS `client_id=`** 조건을 AND로 먼저 건다(문서로 보증되는 방식. `size_constraint GE 0` 류는 추론이라 쓰지 않는다).
- custom response body는 개행 없이 정확히 `Method Not Allowed` / `Access Denied` (채점이 `curl -w " %{http_code}"` 로 `문구 + 공백 + 코드` 를 비교). **후행 개행 여부는 문서로 보증되지 않으므로 배포 후 `curl -s -w '%{size_download}'` 로 각각 18 / 13 인지 실측**한다.

```hcl
custom_response_body {
  key = "method-not-allowed"  content = "Method Not Allowed"  content_type = "TEXT_PLAIN"
}
custom_response_body {
  key = "access-denied"       content = "Access Denied"       content_type = "TEXT_PLAIN"
}

rule {                                    # 규칙 2 (규칙 1은 uri STARTS_WITH /v1/book AND NOT(method EXACTLY POST))
  name = "deny-invalid-client-id"  priority = 2
  action { block { custom_response {
    response_code = 403  custom_response_body_key = "access-denied" } } }
  statement { and_statement {
    statement { byte_match_statement {
      field_to_match { uri_path {} }
      search_string = "/reservation"  positional_constraint = "STARTS_WITH"
      text_transformation { priority = 0  type = "NONE" } } }
    statement { byte_match_statement {                       # 존재 검사
      field_to_match { query_string {} }
      search_string = "client_id="  positional_constraint = "CONTAINS"
      text_transformation { priority = 0  type = "NONE" } } }
    statement { not_statement { statement { regex_match_statement {
      regex_string = "^[A-Za-z][A-Za-z0-9]*[0-9][A-Za-z0-9]*$"
      field_to_match { single_query_argument { name = "client_id" } }   # 이름은 소문자
      text_transformation { priority = 0  type = "URL_DECODE" }
      text_transformation { priority = 1  type = "NONE" } } } }
  } }
}
```

  `query_string`은 항상 존재하는 컴포넌트라 존재 검사에 안전하다. `method`는 대문자로 평가된다.

#### 3.11 Monitoring (k8s/monitoring/, k8s/logging/)

**Grafana**

- helm chart, namespace `monitoring`, addon 노드 배치. **저장소가 2026-01-30부로 이전됐다**: `grafana/helm-charts` → **`grafana-community/helm-charts`** (chart 12.7.2 / Grafana 13.1.0 기준).
- admin 비밀번호 `Skills53#`.
- `grafana.ini`: `serve_from_sub_path = true`, `root_url = https://<CF_DOMAIN>/grafana/` — **템플릿 표현식(`%(protocol)s` 등)을 쓰지 않고 절대 URL을 박는다.** 템플릿은 Pod 내부값(`http`, `3000`)으로 치환되어 정적 자원 경로가 깨진다. `serve_from_sub_path`를 켰으므로 **ALB에서 `/grafana` prefix를 벗기면 안 된다**.
- **TG 이름 `gj2026-grafana-tg`는 Ingress로는 만들 수 없다.** LBC가 `k8s-%.8s-%.8s-%.10s` 규칙으로 이름을 강제 생성하며 오버라이드 어노테이션이 없다 → Terraform에서 TG를 선생성하고 **`TargetGroupBinding`** 으로 연결, helm values는 `ingress.enabled: false`.
- CloudWatch 데이터소스를 IRSA(`gj2026-grafana-role`, `CloudWatchReadOnlyAccess` 상당)로 인증.
- **IRSA 함정**: helm 기본 `securityContext` 472/472/472를 바꾸지 않는다. 바꾸면 SDK가 web identity 토큰 파일을 못 읽고 **조용히 노드 EC2 role로 폴백**한다. 필요 권한: `cloudwatch:ListMetrics/GetMetricData/GetMetricStatistics`, `tag:GetResources`, `ec2:DescribeRegions`.
- 대시보드는 ConfigMap 사이드카로 코드 프로비저닝. 제목은 **ConfigMap 키가 아니라 JSON 루트 `title`** 에서 온다. `{"dashboard": {...}}` 래핑 없이 대시보드 JSON을 그대로 넣는다.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: wsi-dashboard
  namespace: monitoring
  labels: { grafana_dashboard: "1" }
data:
  wsi-dashboard.json: |
    { "title": "WSI Dashboard", "uid": "wsi-dashboard",
      "panels": [{
        "type": "timeseries", "title": "Query Count Panel",
        "gridPos": {"h": 9, "w": 12, "x": 0, "y": 0},
        "datasource": {"type": "cloudwatch"},
        "targets": [{
          "namespace": "gj2026/reservation", "metricName": "QueryCount",
          "dimensions": {"client_id": "*"}, "statistic": "Sum",
          "matchExact": true, "period": "60", "region": "ap-northeast-2",
          "label": "${PROP('Dim.client_id')}"
        }] }] }
```

  `*` 와일드카드가 차원 값마다 시리즈를 분리해 `ALL`·`C001` 두 줄이 그려진다. `matchExact: true`는 차원 스키마가 정확히 `[client_id]`인 메트릭만 잡는다(위 EMF와 일치).
- 이미지는 Docker Hub 전용이므로 인터넷 없는 노드가 직접 받을 수 없다 → 로컬 Docker로 private ECR에 미러링(§5 런북).

**Fluent Bit**

- helm `aws-for-fluent-bit`, namespace `logging`, DaemonSet 이름 그대로 `aws-for-fluent-bit`(채점이 `rollout restart ds/aws-for-fluent-bit` 실행).
- app 노드 taint tolerate 필수(book Pod가 app 노드에 있으므로).
- 파이프라인

```ini
[FILTER]
    Name          parser
    Match         kube.*
    Key_Name      log
    Parser        book_access
    Reserve_Data  On

[FILTER]
    Name          rewrite_tag
    Match         kube.*
    Rule          $remote_addr ^10\.0\.10\. book.az.a false
    Rule          $remote_addr ^10\.0\.11\. book.az.b false
    Emitter_Name  book_az_router

[OUTPUT]
    Name              cloudwatch_logs
    Match             book.az.a
    region            ap-northeast-2
    log_group_name    /eks/book-svc/access
    log_stream_name   /book-svc/ap-northeast-2a
    auto_create_group On

[OUTPUT]
    Name              cloudwatch_logs
    Match             book.az.b
    ...               log_stream_name /book-svc/ap-northeast-2b
```

- **`log_stream_template` 단일 output으로 만들지 않는다.** parser 필터는 파싱 실패 레코드를 드롭하지 않고 원본 그대로 통과시키는데, 템플릿은 필드가 없으면 `log_stream_name`으로 폴백하므로 `Server running on port 8080` 같은 줄이 **세 번째 스트림**을 만든다. 채점은 정확히 2개를 기대한다. `rewrite_tag`를 쓰면 `$remote_addr`가 없는 레코드는 두 Rule 모두 스킵 → 태그 `kube.*` 유지 → Match하는 output이 없어 자동 폐기된다(스트림 2개가 구조적으로 보장).
- **태그에는 `/`나 `_`를 쓸 수 없다**(`a-z A-Z 0-9 .-,` 만 허용). 태그는 `book.az.a`, 스트림명 `/book-svc/ap-northeast-2a`는 output에서 따로 지정 — 두 값을 혼동하기 쉽다.

- **핵심**: 채점이 로그 메시지에 `jq -r '.remote_addr'`를 적용한다 → CloudWatch에 **JSON**으로 들어가야 한다. book 앱의 액세스 로그는 평문이므로 정규식 파서로 구조화해야 한다.

```
2026/07/02 08:52:14 access method=GET path=/health status=200 duration=129.699µs remote_addr=10.0.10.66:38602 user_agent="curl/8.18.0"
```

```ini
[PARSER]
    Name   book_access
    Format regex
    Regex  ^(?<ts>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) access method=(?<method>\S+) path=(?<path>\S+) status=(?<status>\d+) duration=(?<duration>\S+) remote_addr=(?<remote_addr>\S+) user_agent="(?<user_agent>.*)"$
    Types  status:integer
```

- **`user_agent`는 `[^"]*`가 아니라 `.*`**: Go `%q`는 내부 따옴표를 `\"`로 이스케이프하므로 `[^"]*`가 그 앞에서 멈춰 매칭 전체가 실패한다.
- **`Time_Key`/`Time_Format`을 걸지 않는다**: Go `LstdFlags`는 타임존이 없는 로컬 시각이고, CRI 파서가 이미 RFC3339Nano 타임스탬프를 넣어둔 상태다. 여기에 Time_Key를 걸면 정확한 값을 부정확한 값으로 덮어써 CloudWatch 이벤트 시각이 통째로 밀린다(10-2의 "8-3 실행 시각과 일치" 판정에 직결).
- 명명 캡처는 Ruby 문법(`(?<name>...)`)이다. `(?P<name>...)`는 동작하지 않는다. `duration`의 `µ`는 UTF-8 인코딩이라 `\S+`로 정상 매칭된다.
- 파싱 실패 레코드(`Server running on port 8080` 등)는 `remote_addr`가 없어 rewrite_tag에 걸리지 않고 자연히 폐기된다.
- `remote_addr`에 찍히는 IP는 ALB 노드의 서브넷 IP이므로 `10.0.10.x`/`10.0.11.x`로 AZ 판별이 성립한다. 단 **book Pod가 두 AZ에 분산**되어 있어야 두 스트림이 모두 생성된다(topologySpreadConstraints).
- 로그 그룹은 채점이 삭제 후 재생성을 기대하므로 `auto_create_group On` 필수(Terraform으로 미리 만들어도 삭제되므로 의존하면 안 됨).
- IRSA: `logs:CreateLogGroup/CreateLogStream/PutLogEvents/DescribeLogStreams`.
- helm values 필수 2줄 — 빼면 중복 전송/불필요 처리가 생긴다.

```yaml
cloudWatchLogs:
  enabled: false   # 차트 기본 output이 Match "*" 라 book.az.* 까지 잡아 중복 전송
filter:
  enabled: false   # 평문 로그라 Merge_Log 가 할 일이 없음
image:
  repository: <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/aws-observability/aws-for-fluent-bit
  tag: "3.4.8"     # stable 태그는 EOL(2026-06-30)된 2.x를 가리키므로 명시 고정
```

- 배포 전 파서 dry-run(로컬에 Docker/WSL이 없으므로 파드 안에서 직접) — 실패 시 정규식 문제인지 IAM 문제인지 즉시 구분된다.

```bash
kubectl -n logging exec ds/aws-for-fluent-bit -- /fluent-bit/bin/fluent-bit \
  -R /fluent-bit/etc/parser_extra.conf \
  -i dummy -p 'dummy={"log":"2026/07/02 08:52:14 access method=GET path=/health status=200 duration=129.699µs remote_addr=10.0.10.66:38602 user_agent=\"curl/8.18.0\""}' \
  -F parser -p 'Key_Name=log' -p 'Parser=book_access' -p 'Reserve_Data=On' -m '*' \
  -o stdout -f 1
```

### 4. 변수 설계 (30% 변동 대비)

| 변수 | 기본값 | 비고 |
|---|---|---|
| `bibunho` | (tfvars 필수) | S3 버킷명 suffix |
| `region` | `ap-northeast-2` | 엔드포인트 서비스명·env에 공유 |
| `name_prefix` | `gj2026` | 전 리소스명 파생 |
| `vpc_cidr` / `private_subnet_cidrs` | 10.0.0.0/16, [10.0.10.0/24, 10.0.11.0/24] | Fluent Bit AZ 판별 정규식도 이 값에서 생성 |
| `azs` | `["ap-northeast-2a","ap-northeast-2b"]` | 로그 스트림 이름과 단일 소스 |
| `cluster_version` | `1.35` | |
| `addon_instance_type` / `app_instance_type` | t3.medium / m5.large | |
| `node_desired_size` | 2 | 두 노드그룹 공통 |
| `table_name` | `books` | env `TABLE_NAME`과 단일 소스 |
| `gsi_name` | `client_id-index` | Lambda 코드에도 주입 |
| `container_port` | 8080 | TG·SG·Service 공유 |
| `image_tag` | `latest` | 채점이 latest 태그를 지정 |
| `grafana_admin_password` | `Skills53#` | |
| `client_id_regex` | `^[A-Za-z][A-Za-z]*[0-9][A-Za-z0-9]*$` | WAF 규칙 변경 대비 |
| `enable_ddb_write_deny` | `true` | 데이터 정리 시 일시 false |

### 5. 배포 순서 (README 런북 초안)

의존 관계상 **Terraform(네트워크·ECR) → 이미지 push → eksctl → Terraform(나머지) → k8s** 순서가 강제된다.
CloudFront VPC Origin은 ALB가, TargetGroupBinding은 TG가 먼저 있어야 한다.

```bash
cd set-06/task-1/terraform
export AWS_REGION=ap-northeast-2

terraform init
terraform apply -target=aws_ecr_repository.book -target=aws_ecr_pull_through_cache_rule.public

aws ecr get-login-password | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com
docker buildx build --platform linux/amd64 --provenance=false \
  --output type=image,name=<ECR_URL>:latest,compression=zstd,compression-level=19,force-compression=true,push=true \
  -f ../app/Dockerfile ../../../shared/provided/set-06-task-1
aws ecr describe-images --repository-name book \
  --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text   # 3145728 이하 확인

terraform apply
terraform output -json > outputs.json

docker pull public.ecr.aws/bottlerocket/bottlerocket-bootstrap:<TAG>
docker tag ... <ECR>/gj2026/br-bootstrap:1.0.0 && docker push <ECR>/gj2026/br-bootstrap:1.0.0
docker pull <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/nginx/nginx:latest   # 4-5 대비

cd ../eksctl && envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml
aws eks update-kubeconfig --name gj2026-eks-cluster
kubectl get nodes    # 이름 포맷 즉시 확인 (실패 시 self-managed nodeGroups로 fallback)

kubectl set env daemonset aws-node -n kube-system ENABLE_POD_ENI=true
aws eks update-addon --cluster-name gj2026-eks-cluster --addon-name coredns \
  --configuration-values file://addon-coredns.json --resolve-conflicts OVERWRITE

docker pull grafana/grafana:<TAG> && docker tag ... && docker push <ECR>/mirror/grafana:<TAG>

cd ../k8s && kubectl apply -f 00-namespace.yaml
helm upgrade --install aws-load-balancer-controller ...   # addon 노드
kubectl apply -f app/ && helm upgrade --install grafana ... && helm upgrade --install aws-for-fluent-bit ...

```

### 6. 함정·주의사항

1. **서브넷 추가 금지**: 1-1은 VPC 내 전 서브넷을 나열해 정확 비교한다(3번째 서브넷을 만들면 즉시 오답). 단 Gateway Endpoint는 서브넷이 아니라 라우트만 추가하고 그 라우트는 1-2 쿼리에서 자동 제외되므로(§0-2) 안전하다.
2. **NAT 0개**: 계정 전체 `describe-nat-gateways` 개수가 0이어야 한다. 임시로 만든 NAT를 남기면 실패.
3. **ECR 이미지 3MB**: 기본 gzip으로 push하면 3.32MiB로 초과. zstd 압축 push가 유일한 통과 경로이며, 태그는 `latest`.
4. **pull-through cache rule(`ecr-public`)**: 4-5 채점이 이 URL로 nginx를 pull 한다. 룰 누락 = 1.5점 손실.
5. **DynamoDB Deny 정책이 자기 발등을 찍는다**: 정책 활성 상태에서는 관리자도 아이템 삭제 불가 → "데이터 0개" 요구를 먼저 처리하는 순서를 지킨다.
6. **WAF method 규칙 스코프**: `/v1/book` 한정. 전역 적용 시 Grafana·Lambda 조회가 모두 차단된다.
7. **8-1의 Hit 조건**: `/`가 CloudFront Function으로 `/index.html`이 되어 캐시 키가 합쳐져야 세 번째 요청이 Hit. `default_root_object`만으로는 불가.
8. **Fluent Bit는 파싱이 본체**: 평문 액세스 로그를 JSON으로 구조화하지 않으면 채점의 `jq .remote_addr`가 실패한다.
9. **book Pod AZ 분산**: 한쪽 AZ에만 있으면 10-1의 로그 스트림이 1개만 생겨 감점.
10. **EKS 엔드포인트 public 활성**: private-only로 만들면 채점 CloudShell의 kubectl이 동작하지 않는다(4-1 `True True`도 불일치).
11. **채점은 CloudShell**: 로컬에서만 되는 구성(포트포워딩 등)에 의존하지 않는다.
12. **CloudFront 반영 지연**: 배포·무효화에 최대 3분 이상. 경기 후반 수정 시간을 계산에 넣는다.
13. **`ami:` 지정 금지**: amiType이 `CUSTOM`이 되어 4-2 문자열 비교가 깨진다.
14. **t3.medium에는 SGP가 동작하지 않는다**: t 패밀리는 trunk ENI 미지원. app(m5.large) 노드에만 적용.
15. **book Pod에 probe를 달지 않는다**: probe를 살리려면 노드 SG를 8080에 열어야 하고, 그 순간 4-5가 통과된다(=감점).
16. **zstd 이미지는 로컬 `docker run` 불가**: 구동 검증은 클러스터에서만. 사전 리허설 필수.
17. **WAF 정규식 앵커 누락**: 부분 매칭이라 `홍길동`의 URL 인코딩 안 `B8`에 매칭되어 통과해버린다.
18. **WAF `client_id` 존재 검사 누락**: `NOT(regex)` 단독이면 파라미터 없는 8-3 요청까지 403이 된다.
19. **`AllViewerExceptHostHeader` 누락**: 쿼리스트링이 오리진에 안 가서 WAF가 `client_id`를 못 본다 → 9-2 전멸.
20. **Grafana TG 이름은 Ingress로 못 만든다**: LBC가 이름을 강제 생성. Terraform TG + TargetGroupBinding 필수.
21. **Grafana `securityContext` 472 변경 금지**: IRSA 토큰을 못 읽고 조용히 노드 role로 폴백한다.
22. **PTC 첫 pull 워밍업**: 노드에 인터넷이 없으므로 인터넷 있는 CloudShell/로컬에서 미리 pull 해 캐시를 채운다. 노드 role에 `ecr:BatchImportUpstreamImage`, `ecr:CreateRepository` 필요.
23. **Lambda는 ALB 타깃그룹이 아니다**: task.md가 Target Group 이름을 book/grafana 2개만 명시한다. Lambda는 Function URL + CloudFront OAC로 직접 연결한다(§0-1).
24. **WAF는 CLOUDFRONT scope, us-east-1**: REGIONAL로 만들어 ALB에 붙이면 Lambda(`/reservation`) 요청은 검사하지 못한다. 반드시 CloudFront 배포에 `web_acl_id`로 직접 연결.
25. **DynamoDB Gateway Endpoint 필수**: DynamoDB는 Interface Endpoint 자체가 없다(Gateway 전용). rtb-a/b에 연결해도 1-2는 깨지지 않는다(§0-2, jmespath 실측 확인).
26. **Pod SG egress는 DynamoDB를 prefix-list로 열어야 한다**: Gateway Endpoint는 ENI가 없어 "endpoint SG" 참조로는 안 열린다.
27. **SGP 파드의 DNS는 노드 SG 인그레스가 열려야 한다** (실측 2026-07-23): CoreDNS 는 노드 ENI 뒤에 있어서 branch ENI(book pod SG) 발 53 이 노드 SG 인그레스에서 막힌다 → 모든 이름 해석 행 → STS/DDB 불통 → 8-2 504. `vpc.tf` 의 `node_dns_from_book_pod` 규칙이 해결. (book pod SG egress 에 서비스 CIDR 172.20.0.0/16 도 함께 허용.)
28. **scratch 이미지에 CA 번들 필수** (실측): 없으면 Go SDK 의 STS/DDB TLS 가 `x509: certificate signed by unknown authority` 로 전멸. 전체 번들은 2-2 의 3MB 초과 → Amazon/Starfield 루트만 추출(~7KB, Dockerfile 참조).
29. **book 바이너리(v1.0.1, 8.4MB)는 zstd -19/-22 로도 3.07MB** — 3MB 초과. UPX `--best --lzma` 선압축으로 2.42MB (Dockerfile 빌드 스테이지, 원본 무수정). 채점 전 `imageSizeInBytes` 반드시 재확인.
30. **Lambda OAC 는 `lambda:InvokeFunctionUrl` 외에 `lambda:InvokeFunction` statement 도 필요** (실측): 전자만 있으면 서명이 유효해도 generic `Forbidden`. 공식 문서의 add-permission 2개 세트를 그대로 반영(`lambda.tf` cf_oac_invoke).
31. **grafana 차트 Service 기본 포트는 80** (실측): TGB serviceRef 가 3000 을 참조하므로 values 에 `service.port: 3000` 필수. 없으면 `BackendNotFound` 로 타깃 미등록 → 10-2 불가.
32. **재배포 후 낡은 `.env.ps1` 로 k8s 렌더 금지** (실측): TGB 가 삭제된 TG ARN, SGP 가 옛 SG 를 물고 들어가 조용히 실패한다(`TargetGroupNotFound`). terraform 재 apply 후에는 반드시 README 3단계 env 재주입 → TGB/SGP 재렌더·재적용. TGB 의 targetGroupARN 은 불변 필드라 delete→apply.
33. **8-3/8-4 JSON 키 순서** (실측): DDB 응답 dict 순서는 비결정(concert_name 이 앞으로 옴). 채점 기대 문자열과 맞추려 `index.py` 에서 username→email→concert_name 순으로 재구성.
34. **CloudFront VPC Origin 의 소스 IP 는 VPC 내부 ENI 가 아니라 CF POP 공인 대역** (Flow Log 실측, 최중요): ENI 에서 나갈 땐 ENI IP 로 보였지만 ALB ENI 도착 시 src=54.182.x → VPC CIDR 허용만으론 REJECT → 8-2/10-2 전부 504. ALB SG 는 `com.amazonaws.global.cloudfront.origin-facing` managed prefix list 를 허용해야 한다(공식 문서 옵션 1). 또한 VPC origin 리소스는 배포에 연결된 동안 이름 포함 완전 불변(update/delete 409).
35. **인라인 ingress 를 쓰는 SG 에 별도 `aws_security_group_rule` 을 섞으면 다음 full apply 가 그 규칙을 삭제한다** (실측 재발 사례: node SG 의 CoreDNS 53 규칙이 사라져 8-2 재붕괴). 같은 SG 의 규칙은 한 방식으로 통일.
36. **topologySpreadConstraints(DoNotSchedule)는 스케줄 시점에만 평가** (실측): 롤링 서지 중 기존 파드가 카운트돼 재배포 후 한 AZ 로 몰릴 수 있다(레이블 같은 디버그 파드도 카운트 오염). `kubectl get pods -o wide` 로 AZ 확인 후 몰린 쪽 파드 1개 삭제하면 제약이 반대 AZ 로 강제한다. 10-1(AZ별 스트림)·HA 요구에 직결.
37. **DynamoDB 리소스 정책은 재적용 직후 전파 지연이 있다** (실측 2026-07-23): `terraform apply` 로 `aws_dynamodb_resource_policy`를 destroy→recreate 한 직후 곧바로 `put-item` 시도하면 Deny 이전에 성공해버린다(채점 3-3 오탐 위험). 몇 초~분 뒤엔 정상 Deny. **채점 전 정리에서 Deny 재적용 후 `put-item` 이 AccessDenied 를 낼 때까지 대기(폴링)한 뒤 채점 시작**(README 8단계에 반영). 전파 전 통과된 put-item 은 David 같은 유령 항목을 남겨 8-3 까지 오염시킨다.
38. **채점 시작 시 books 테이블은 반드시 비어 있어야 한다** (실측 감점 사례 2026-07-23): mark.sh 8-2 가 시드 2건(Alice/C001, Bob/C002)을 `book-app-role`(Deny 예외)로 POST 하고, 8-3(전체 scan=2건)·8-4(C001 query=1건)로 검증한다. 잔여 데이터가 있으면 개수/중복 불일치로 8-3·8-4 동시 실패(각 1.5점). 오염원: (a) 10-1 리허설의 `POST /v1/book`(매 요청이 booking 삽입 — 리허설은 GET /v1/book 405 로 대체하면 무삽입), (b) 3-3 전파지연으로 통과된 put-item, (c) mark.sh 중복 실행. **채점 전 정리(8단계)에서 전삭제 필수, 재채점 시마다 반복.** mark.sh 8-3 은 "순서 무관"이라 [Alice,Bob]/[Bob,Alice] 둘 다 정답.

### 6.2 문서로 확정 안 된 항목 (배포 후 실측)

| 항목 | 검증 방법 |
|---|---|
| WAF 커스텀 응답 본문 후행 개행 | `curl -s -o /dev/null -w '%{size_download}\n' $CF/v1/book` → 18 / `?client_id=123abc` → 13 |
| CLOUDFRONT scope Web ACL이 Lambda Function URL 오리진 앞에서도 정상 evaluate되는지 | `?client_id=123abc`로 `/reservation` 호출 시 403 확인 |
| 커스텀 노드명 + `provider-id` / CCM | `kubectl get nodes` 가 Ready + 이름 포맷 일치 |
| zstd 이미지 노드 구동 | Pod Running 도달 |
| Grafana sidecar 대시보드 JSON 래핑 형태 | UI에 `WSI Dashboard` 노출 확인 |

### 6.1 리스크 순위 (사전 검증 대상)

| 순위 | 항목 | 리스크 | 대응 |
|---|---|---|---|
| 1 | 커스텀 노드명 + `provider-id` / CCM 상호작용 | **실측으로 원인 확정(§3.5.2)** — access entry username 불일치. aws-auth `{{SessionName}}` 매핑 + desired 0 → scale-up 전략 채택, 미확정 3항목 실측 남음 | 카나리 노드그룹(README 문제해결)으로 5분 내 확정 |
| 2 | zstd 이미지 노드 구동 | 로컬 검증 불가 | 사전 배포 리허설 |
| 3 | SGP strict + TargetGroupBinding 조합 | 타깃이 unhealthy로 남을 수 있음 | ALB SG→Pod SG 8080 규칙 실측 |
| 4 | eksctl managed nodegroup의 `bottlerocket.settings` 반영 | 과거 user-data 미반영 버그 이력 | 생성 후 `kubectl get nodes` 즉시 확인, 실패 시 self-managed `nodeGroups`로 fallback |
| 5 | CLOUDFRONT scope Web ACL의 us-east-1 provider 설정 실수 | apply 시 리전 오류로 실패 | provider alias 명시, plan 단계에서 확인 |

### 7. 검증 시드

```bash
CF=https://$(cd terraform && terraform output -raw cloudfront_domain)

curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" $CF            # 200 Miss
curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" $CF/index.html # 200 Hit
curl -sX POST -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Busan2025"}' $CF/v1/book
curl -s $CF/reservation
curl -s "$CF/reservation?client_id=C001"
curl -s -w " %{http_code}\n" $CF/v1/book                       # Method Not Allowed 405
curl -s -w " %{http_code}\n" "$CF/reservation?client_id=123abc" # Access Denied 403
kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers   # gj2026.<id>.(addon|app).node
kubectl run nginx-test -n skills --image=<ECR>/ecr-public/nginx/nginx:latest --restart=Never
kubectl exec -n skills nginx-test -- curl -m 5 -sS http://book-svc:8080/health   # timeout 이어야 정상
aws logs describe-log-streams --log-group-name /eks/book-svc/access             # 스트림 2개
```

로컬 실측(동일 md5 바이너리를 set-08에서 확인): `GET /health`→200, 미정의 경로→404, DDB 미연결 POST→500, 액세스 로그는 위 §3.11 평문 형식.
