# set-06 / task-1 설계 (Solution Architecture)

EKS(Bottlerocket) 위에 Book API를 배포하고, CloudFront 단일 엔드포인트로 S3 정적 페이지 · ALB API · Lambda 조회 API · Grafana를 함께 서비스하는 과제. 전 리소스 `ap-northeast-2`(WAF Web ACL만 AWS 제약상 예외, §3.10). **NAT 없음 / Private Subnet 2개뿐**이라는 제약이 설계 전반을 지배한다.

## 0. 재검토 기록 (원본 PDF 재확인 + 실측)

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

## 1. 요구사항 ↔ 채점항목 ↔ 리소스 매핑

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

## 2. 디렉토리 구조

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

## 3. 도메인별 설계

### 3.1 VPC / Endpoint (vpc.tf)

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

### 3.2 KMS (kms.tf)

CMK 3개 + alias. 채점이 alias 이름으로 역추적하므로 alias 정확성이 곧 점수.

| alias | 용도 | 키 정책 추가 사항 |
|---|---|---|
| `alias/gj2026-db-key` | DynamoDB SSE | book/Lambda 역할에 Decrypt·GenerateDataKey |
| `alias/gj2026-s3-key` | S3 기본 암호화 | **CloudFront OAC(`cloudfront.amazonaws.com`)에 Decrypt·GenerateDataKey**, `AWS:SourceArn`=배포 ARN 조건 |
| `alias/gj2026-eks-key` | EKS Secret 봉투 암호화 | EKS 서비스 사용 허용(기본 root 위임으로 충분) |

S3 CMK에 CloudFront 권한을 빠뜨리면 8-1이 전부 실패한다(SSE-KMS 객체를 OAC가 못 읽음).

### 3.3 ECR + 컨테이너 이미지 (ecr.tf, app/Dockerfile)

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

### 3.4 DynamoDB (dynamodb.tf)

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

### 3.5 EKS (eksctl/cluster.yaml)

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

#### 3.5.1 노드 이름 커스터마이징 (채점 4-3, 1.5점)

- Bottlerocket에는 셸이 없어 `preBootstrapCommands`가 성립하지 않고, eksctl 공식 문서도 **Bottlerocket에서 `overrideBootstrapCommand` 미지원**을 명시한다. managed nodegroup + launch template 조합에서도 두 필드 모두 unsupported.
- `settings.kubernetes.hostname-override-source`는 `private-dns-name` / `instance-id` 두 값만 지원 → 노드명이 `i-0abc...` 형태로만 나오므로 요구 포맷 불가.
- 유일한 경로는 **bootstrap container**. Bottlerocket 공식 문서 기준 bootstrap container는 *kubelet보다 먼저 실행되고, 모두 종료될 때까지 systemd가 다음 target으로 넘어가지 않는다.* 즉 kubelet이 뜨기 전에 `hostname-override`를 심을 수 있다.

```yaml
managedNodeGroups:
  - name: gj2026-eks-addon-nodegroup
    amiFamily: Bottlerocket
    instanceType: t3.medium
    desiredCapacity: 2
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

# 키에 하이픈이 있어 dotted 형식이 아닌 --json 형식을 써야 한다
apiclient set --json "{\"settings\":{\"kubernetes\":{
  \"hostname-override\":\"gj2026.${IID}.addon.node\",
  \"provider-id\":\"aws:///${AZ}/${IID}\"}}}"
```

- **`provider-id`를 반드시 함께 설정한다.** EKS 1.35는 external cloud provider를 쓰기 때문에, 노드 이름이 private DNS name이 아니면 cloud controller manager가 노드↔EC2 매칭에 실패해 `node.cloudprovider.kubernetes.io/uninitialized` taint가 벗겨지지 않고 NotReady에 머물 수 있다. **이 조합은 문서만으로 100% 확정되지 않았으므로 클러스터에서 1회 실측 검증이 필수**(최우선 리스크).
- bootstrap container 이미지는 `public.ecr.aws/bottlerocket/bottlerocket-bootstrap` 기반으로 **로컬에서 private ECR로 직접 push**한다. ECR pull-through cache는 최초 pull 시 인터넷 경로가 필요할 수 있어 노드 부팅 경로에 두면 위험하다. 이 이미지는 kubelet이 아니라 호스트의 `host-ctr`가 인스턴스 프로파일 권한으로 당기므로 노드 IAM에 ECR read 권한이 있어야 한다.
- 검증: `kubectl get nodes` 로 4개 노드가 `gj2026.i-xxxx.addon.node` / `...app.node` 로 뜨는지, `aws eks list-access-entries` 로 노드 role access entry가 생성됐는지 확인.

### 3.6 애플리케이션 (k8s/app/)

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

#### 3.6.1 "ALB에서 오는 요청만 수신" 구현 (채점 4-5, 1.5점)

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
# 클러스터 role에 AmazonEKSVPCResourceController 필요 (eksctl 기본 부여)
# 모드 변경은 신규 Pod에만 적용 → 이후 rollout restart
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

### 3.7 ALB (alb.tf)

- `gj2026-alb`, **internal**, private subnet a/b, HTTP:80 리스너.
- Target Group **2종**(task.md 9번 항목이 이름을 딱 2개만 명시 — Lambda용 3번째 TG는 없다, §0-1):
  - `gj2026-book-tg`: type ip, 8080, health check `/health`
  - `gj2026-grafana-tg`: type ip, 3000, health check `/grafana/api/health`
- 리스너 규칙: `/v1/book*`→book, `/grafana*`→grafana, default fixed-response 404.
- WAF는 이 ALB에 붙이지 않는다 — CloudFront 엣지에 붙인다(§3.10).

Lambda는 **ALB 타깃그룹이 아니라 Function URL로 CloudFront에 직접 연결**한다(§3.8). 최초 설계는 "Web ACL 1개로 CloudFront·ALB를 동시에 커버할 수 없다"는 이유로 ALB 경유를 택했지만, 이는 WAF를 REGIONAL/ALB에 붙인다는 전제 자체가 원본 다이어그램·리소스명 목록과 맞지 않았다(§0-1). WAF를 CloudFront(CLOUDFRONT scope)에 붙이면 하나의 Web ACL이 엣지에서 모든 경로를 검사한 뒤 ALB든 Lambda든 원하는 오리진으로 보낼 수 있어, 굳이 Lambda를 ALB 뒤에 둘 필요가 없다.

### 3.8 Lambda (lambda.tf, lambda/index.py)

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

### 3.9 S3 + CloudFront (s3.tf, cloudfront.tf)

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

### 3.10 WAF (waf.tf)

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

### 3.11 Monitoring (k8s/monitoring/, k8s/logging/)

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
# 최상위에 "remote_addr"=>"10.0.10.66:38602" 가 찍히면 통과
```

## 4. 변수 설계 (30% 변동 대비)

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

## 5. 배포 순서 (README 런북 초안)

의존 관계상 **Terraform(네트워크·ECR) → 이미지 push → eksctl → Terraform(나머지) → k8s** 순서가 강제된다.
CloudFront VPC Origin은 ALB가, TargetGroupBinding은 TG가 먼저 있어야 한다.

```bash
# 0) 로컬 환경 변수
cd set-06/task-1/terraform
export AWS_REGION=ap-northeast-2

# 1) 네트워크 + ECR + KMS + DynamoDB 먼저
terraform init
terraform apply -target=aws_ecr_repository.book -target=aws_ecr_pull_through_cache_rule.public

# 2) 이미지 빌드·push (로컬 Docker Desktop, zstd 압축)
aws ecr get-login-password | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com
docker buildx build --platform linux/amd64 --provenance=false \
  --output type=image,name=<ECR_URL>:latest,compression=zstd,compression-level=19,force-compression=true,push=true \
  -f ../app/Dockerfile ../../../shared/provided/set-06-task-1
aws ecr describe-images --repository-name book \
  --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text   # 3145728 이하 확인

# 3) 나머지 AWS 리소스
terraform apply
terraform output -json > outputs.json

# 3.5) bootstrap container 이미지 push + 풀스루 캐시 워밍업 (인터넷 있는 로컬에서)
docker pull public.ecr.aws/bottlerocket/bottlerocket-bootstrap:<TAG>
docker tag ... <ECR>/gj2026/br-bootstrap:1.0.0 && docker push <ECR>/gj2026/br-bootstrap:1.0.0
docker pull <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/nginx/nginx:latest   # 4-5 대비

# 4) EKS 클러스터
cd ../eksctl && envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml
aws eks update-kubeconfig --name gj2026-eks-cluster
kubectl get nodes    # 이름 포맷 즉시 확인 (실패 시 self-managed nodeGroups로 fallback)

# 4.5) Pod SG 활성화 + addon 배치
kubectl set env daemonset aws-node -n kube-system ENABLE_POD_ENI=true
aws eks update-addon --cluster-name gj2026-eks-cluster --addon-name coredns \
  --configuration-values file://addon-coredns.json --resolve-conflicts OVERWRITE

# 5) Grafana 이미지 미러링(Docker Hub 전용이라 풀스루 불가)
docker pull grafana/grafana:<TAG> && docker tag ... && docker push <ECR>/mirror/grafana:<TAG>

# 6) k8s 리소스
cd ../k8s && kubectl apply -f 00-namespace.yaml
helm upgrade --install aws-load-balancer-controller ...   # addon 노드
kubectl apply -f app/ && helm upgrade --install grafana ... && helm upgrade --install aws-for-fluent-bit ...

# 7) 채점 전 정리
#   - DynamoDB 아이템 0개 (enable_ddb_write_deny=false → 삭제 → true)
#   - CloudFront invalidation
```

## 6. 함정·주의사항

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

## 6.2 문서로 확정 안 된 항목 (배포 후 실측)

| 항목 | 검증 방법 |
|---|---|
| WAF 커스텀 응답 본문 후행 개행 | `curl -s -o /dev/null -w '%{size_download}\n' $CF/v1/book` → 18 / `?client_id=123abc` → 13 |
| CLOUDFRONT scope Web ACL이 Lambda Function URL 오리진 앞에서도 정상 evaluate되는지 | `?client_id=123abc`로 `/reservation` 호출 시 403 확인 |
| 커스텀 노드명 + `provider-id` / CCM | `kubectl get nodes` 가 Ready + 이름 포맷 일치 |
| zstd 이미지 노드 구동 | Pod Running 도달 |
| Grafana sidecar 대시보드 JSON 래핑 형태 | UI에 `WSI Dashboard` 노출 확인 |

## 6.1 리스크 순위 (사전 검증 대상)

| 순위 | 항목 | 리스크 | 대응 |
|---|---|---|---|
| 1 | 커스텀 노드명 + `provider-id` / CCM 상호작용 | 노드가 NotReady에 머물 수 있음. 문서로 완전 확정 안 되는 지점 | 사전에 클러스터 1회 생성해 실측 |
| 2 | zstd 이미지 노드 구동 | 로컬 검증 불가 | 사전 배포 리허설 |
| 3 | SGP strict + TargetGroupBinding 조합 | 타깃이 unhealthy로 남을 수 있음 | ALB SG→Pod SG 8080 규칙 실측 |
| 4 | eksctl managed nodegroup의 `bottlerocket.settings` 반영 | 과거 user-data 미반영 버그 이력 | 생성 후 `kubectl get nodes` 즉시 확인, 실패 시 self-managed `nodeGroups`로 fallback |
| 5 | CLOUDFRONT scope Web ACL의 us-east-1 provider 설정 실수 | apply 시 리전 오류로 실패 | provider alias 명시, plan 단계에서 확인 |

## 7. 검증 시드

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
