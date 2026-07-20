---
title: "도메인별 설계"
sidebar:
  order: 4
---

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
