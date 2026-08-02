# 실 배포·실채점 실측 로그 (2026-08-02)

> set-08/task-2 4모듈을 런북 그대로 배포하고 CloudShell에서 `mark/mark2-N.sh`를 실행한 기록.
> 계정 600440344359. 배포는 로컬(IAM user `admin`), 채점은 CloudShell(콘솔 root 로그인).
> 런북 개선점은 [FEEDBACK.md](FEEDBACK.md), 함정·결정은 [NOTES.md](NOTES.md).

## 0. 사전 점검

- IAM 권한 프로브: `skills-iam-probe` role 생성·삭제 모두 성공 → IAM 생성 권한 있음.

## 1. terraform apply 결과

| 모듈 | 리전 | 결과 | 소요 |
|------|------|------|------|
| module-1-nosql | ap-northeast-2 | 22 added, 0 changed, 0 destroyed | ~7분 (DocumentDB 인스턴스 병목) |
| module-2-lattice | ap-northeast-1 | 24 added | ~2분 |
| module-3-event-handling | ap-southeast-1 | 16 added | ~1분 |
| module-4-sqs-scaling | us-west-2 | 30 added | ~3분 (NAT GW 병목) |

module-4 후속 단계: `eksctl create cluster` **19분**(11:00:08 → 11:19:10 ready), CloudShell docker build+push ~2분, helm(karpenter+keda) ~2분.

## 2. 로컬 검증 실측

### module-1 (ap-northeast-2)

```
/health   → {"status": "ok", "database": "skills_retail", "port": 27017, "tls": true}
/v1/admin/summary → counts {orders: 8, products: 6, sessions: 3}
                    dateFieldTypes 전부 "datetime"
/v1/admin/indexes → orders 4개 / products 3개 / sessions 4개
                    sessions.expiresAt 에 expireAfterSeconds: 0
/v1/orders/O-1001            → PENDING, W-A, totalAmount 135.5, items 2건
/v1/customers/C001/orders    → O-1006 / O-1001 / O-1004 (3건)
/v1/orders/pending?from=2026-06-01&to=2026-06-08 → O-1001 / O-1003 / O-1006 (3건)
/v1/products/low-stock?warehouseId=W-A → P-BLU-003(stock 1) / P-RED-001(stock 4), P-GRN-002 제외
```

지급 dataset `sessions.expiresAt` = 2026-12-01/02/03 → 채점 시점(2026-08-02)보다 미래. TTL 자동 삭제 미발생 확인.

### module-2 (ap-northeast-1)

```
http://<client_ip>/health                  → {"status": "ok", "app": "client"}
http://<client_ip>/v1/client/orders?id=1001 → {"client": "ok", "service": {"order_id": "1001", "via": "vpc-lattice"}}
```

감점 축 직접 확인:

```
skills-lattice-service-ec2-sg ingress: tcp/8080, IpRanges [], PrefixListIds [pl-0596057d86614af83]
  → CIDR 소스 0개 (0.0.0.0/0 없음)
skills-lattice-service-ec2 PublicIpAddress = None   (client-ec2 만 3.112.129.113)
```

### module-3 (ap-southeast-1)

Lambda 직접 invoke (채점 3-5 동일 payload):

```
{"status": "RESTORED", "revokedPermissionCount": 1, "publishStatus": "SNS_PUBLISHED"}
IpPermissions → []
```

실경로(CloudTrail→EventBridge→Lambda): TCP/22 추가 후 **19.6초**만에 복구 완료 (기준 180초).
`get-trail-status IsLogging` → `true`.

### module-4 (us-west-2)

k8s apply 후 상태:

```
scaledobject sqs-worker-scaledobject   MIN 0  MAX 6  READY True  TRIGGERS aws-sqs-queue
triggerauthentication sqs-worker-trigger-auth   PODIDENTITY aws
nodepool skills-sqs-nodepool  → READY True
ec2nodeclass skills-sqs-nodeclass → READY True
karpenter/keda controller pod 전부 Running (Fargate)
```

스케일 검증 (SQS 12건 발송):

```
after 60s : 메시지 12 / pod 6개 Running / Karpenter 노드 2대 (AL2023, containerd 2.2.5)
after 120s: 메시지 0  / deployment 0/0
after 180s: 노드 NotReady(consolidation 중)
+90s      : pod 0, Karpenter 노드 0
```

CloudShell kubectl: `aws eks update-kubeconfig` 후 최초 `Unauthorized`
→ access entry 추가(root principal) 후 `kubectl get nodes` 정상 (fargate 8 + karpenter 2).

## 3. CloudShell 채점 실행 결과

mark 스크립트는 점수를 출력하지 않는다 — 항목별 증거만 덤프한다. 판정은 사람이 한다.

| 스크립트 | 리전 | 종료 코드 | 결과 파일 | 소요 |
|----------|------|-----------|-----------|------|
| mark2-1.sh | ap-northeast-2 | 0 | asgmt2_module1_check_result.txt (8292B) | ~2분 |
| mark2-2.sh | ap-northeast-1 | 0 | asgmt2_module2_check_result.txt (8537B) | ~2분 |
| mark2-3.sh | ap-southeast-1 | 0 | asgmt2_module3_check_result.txt (133줄) | ~2.5분 |
| mark2-4.sh | us-west-2 | 0 | asgmt2_module4_check_result.txt (18269B) | **~11분** |

### 항목별 증거 (grep 확인)

**module-1**

```
[1-1] DocumentDB cluster Status: available / instance Status: available
[1-2] Secret + Client EC2 구성 출력됨
[1-3] counts {orders:8, products:6, sessions:3}, dateFieldTypes datetime
[1-4] indexes 출력, sessions.expiresAt expireAfterSeconds 0
[1-5] O-1001 / C001 주문 / 기간 내 PENDING / W-A low-stock 정상
```

**module-2**

```
[2-1] VPC 구성 출력
[2-2] Client/Service EC2 및 앱 출력
[2-3] Service Dns skills-lattice-order-service-...on.aws, Status ACTIVE, SN-VPC association 2건
[2-4] Target Group Status ACTIVE, target 8080 HEALTHY (i-0e60febae68b72bd8)
[2-5] {"client": "ok", "service": {"order_id": "1001", "via": "vpc-lattice"}}
```

**module-3**

```
[3-1] VPC/EC2/SG (GroupName skills-ceh-protected-sg)
[3-2] Inbound: []   ← 보호 SG inbound 0개
[3-3] FunctionName skills-ceh-remediate-fn / Handler remediate_security_group.lambda_handler
      Runtime python3.12 / State Active
[3-4] IsLogging True, LatestDeliveryError None
      Rule State ENABLED, EventPattern AuthorizeSecurityGroupIngress
      Target Arn = lambda, lambda permission AllowEventBridgeInvoke
[3-5] RESTORED / revokedPermissionCount 1 / SNS_PUBLISHED, poll=1 에서 inbound_count=0
      로그 그룹 /aws/lambda/skills-ceh-remediate-fn 존재
```

**module-4**

```
[4-1] EKS cluster + fargate 노드 8대 Ready
[4-2] SQS queue + IRSA ServiceAccount 출력
[4-3] keda 3개 pod / karpenter 1개 pod 전부 Running, 전부 fargate-ip-* 노드에 배치
[4-4] worker deployment + ScaledObject 출력
[4-5] NodePool spec: labels skills-nodepool=event-worker,
      nodeClassRef skills-sqs-nodeclass, capacity-type on-demand,
      instance-type [t3.medium, t3.large]
[4-6] sent=12
      after_60s : sqs-worker 3/6→6, pod 6개, Karpenter 노드 2대
                  nodeclaim skills-sqs-nodepool-lgd8z / -mkzt5 (t3.medium, on-demand, us-west-2b)
      after_120s: 메시지 0, deployment 0/0, pod Completed/Terminating
```

4-5 시점엔 minReplicaCount 0이라 Worker Pod가 없지만, 공식 판정 기준이 "4-6 Scale Out 출력 결과를 포함해 판정"을 명시 → 4-6 출력으로 커버됨을 실측으로 확인.

## 4. 판정 대조 결과

`provided/008_chall_2nd_patched_0801.md` 판정 기준과 대조해 20개 항목(1-1~1-5, 2-1~2-5, 3-1~3-5, 4-1~4-6) 전부 기대 출력 일치. 불일치 0건.

주의: 결과 파일 전문을 정독한 게 아니라 항목별 핵심 라인을 grep으로 확인했다. 점수는 사람이 매긴다.
