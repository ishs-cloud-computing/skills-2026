# set-08 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 4개 고정. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 리전 | 채점 커버 | 미해결 |
|------|------|------|-----------|--------|
| 1 | nosql | ap-northeast-2 | 5/5 (`[x]` 실채점 통과 2026-08-02) | 없음 |
| 2 | lattice | ap-northeast-1 | 5/5 (`[x]` 실채점 통과 2026-08-02) | 없음 |
| 3 | event-handling | ap-southeast-1 | 5/5 (`[x]` 실채점 통과 2026-08-02) | 없음 |
| 4 | sqs-scaling | us-west-2 | 6/6 (`[x]` 실채점 통과 2026-08-04) | 없음 |

### module-1 채점 커버리지 (mark2-1.sh ↔ 구현)
<!-- [x] apply 후 mark2-1.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->

- [x] 1-1 DocumentDB Cluster 및 Instance 구성 — `terraform/docdb.tf`: cluster `skills-nosql-docdb-cluster`(storage_encrypted + 전용 KMS `alias/skills-nosql-docdb`, backup 1일, port 27017) + instance `skills-nosql-docdb-instance-1`(db.t3.medium) — 실채점 통과: cluster·instance Status available (2026-08-02)
- [x] 1-2 Secret 및 Client EC2 구성 — `terraform/secrets.tf`(`skills-nosql-docdb-secret`: username/password/host, host는 scheme·port 없는 cluster endpoint) + `terraform/ec2.tf`(`skills-nosql-client-ec2`, public 서브넷 Public IP) — 실채점 통과: Secret + Client EC2 출력 (2026-08-02)
- [x] 1-3 Client Application 및 데이터 적재 — `terraform/userdata.sh.tftpl`: pip boto3·pymongo + `global-bundle.pem` 다운로드 + systemd `serve` + `seed` 재시도 루프(최대 ~10분). counts 8/6/3 + BSON Date 는 지급 앱 seed 가 보장 — 실채점 통과: counts 8/6/3, dateFieldTypes datetime (2026-08-02)
- [x] 1-4 Index 및 TTL 구성 — `terraform/index_setup.py.tftpl`: 과제지 3-3 인덱스 8개(orders 3·products 2·sessions 3, `expiresAt` TTL `expireAfterSeconds: 0`) — 지급 앱엔 생성 코드가 없어 별도 스크립트 (결정 로그) — 실채점 통과: indexes 출력, `sessions.expiresAt` expireAfterSeconds 0 (2026-08-02)
- [x] 1-5 NoSQL 조회 기능 검증 — 지급 앱 조회 로직 + 1-3 적재·1-4 인덱스 전제. 엔드포인트 4개 200 은 README 3단계에서 사전 확인 — 실채점 통과: 조회 4종 정상 (2026-08-02)

### module-2 채점 커버리지 (mark2-2.sh ↔ 구현)
<!-- [x] apply 후 mark2-2.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->

- [x] 2-1 기본 VPC 구성 — `terraform/vpc.tf`: Client VPC(`skills-lattice-client-vpc` 10.61.0.0/16)·Service VPC(`skills-lattice-service-vpc` 10.62.0.0/16) + public 서브넷 각 1개, peering/TGW 없음 — 실채점 통과: VPC 구성 출력 (2026-08-02)
- [x] 2-2 Client/Service EC2 및 애플리케이션 구성 — `terraform/ec2.tf`: `provided/module-2/{client_app.py,service_app.py}` 무수정 base64 user-data, client는 Public IP(:80)·service는 Public IP 없이 서비스 VPC 내부(:8080) — 실채점 통과: Client/Service EC2 및 앱 출력 (2026-08-02)
- [x] 2-3 VPC Lattice Service Network 및 Service 구성 — `terraform/lattice.tf`: `aws_vpclattice_service_network.this`(name=`skills-lattice-sn`) + `aws_vpclattice_service.order`(name=`skills-lattice-order-service`, dns_entry 노출) + SN-Service association — 실채점 통과: Service Status ACTIVE, SN-VPC association 2건 (2026-08-02)
- [x] 2-4 Target Group, Listener, Security Group 구성 — `terraform/lattice.tf`의 `aws_vpclattice_target_group.order`(INSTANCE, HTTP/8080, health check `/health`) + `aws_vpclattice_listener.http`(HTTP/80→TG forward) + `terraform/sg.tf`의 service SG(prefix list 소스만) — 실채점 통과: Target Group ACTIVE, target 8080 HEALTHY (2026-08-02)
- [x] 2-5 End-to-End 기능 검증 — `ec2.tf`의 client user-data가 `SERVICE_URL`을 `aws_vpclattice_service.order.dns_entry[0].domain_name`으로 terraform 참조 주입 → `client_app.py`가 `/v1/client/orders?id=1001` 호출 시 Lattice 경유로 `service_app.py`에 도달 — 실채점 통과: `{"client":"ok","service":{"order_id":"1001","via":"vpc-lattice"}}` (2026-08-02)

### module-3 채점 커버리지 (mark2-3.sh ↔ 구현)
<!-- [x] apply 후 mark2-3.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->

- [x] 3-1 기본 VPC, EC2, Security Group 구성 — `terraform/vpc.tf`(`skills-ceh-vpc` 10.73.0.0/16, `skills-ceh-ec2` running + protected SG 연결) + `terraform/sg.tf`(`skills-ceh-protected-sg`) — 실채점 통과 (2026-08-02, 재확인 2026-08-04)
- [x] 3-2 보호 대상 SG 기준 상태 — `terraform/sg.tf`: ingress 리소스 미선언(Inbound 0개) + egress 는 별도 `aws_vpc_security_group_egress_rule` — 실채점 통과: Inbound `[]` (2026-08-02, 재확인 2026-08-04)
- [x] 3-3 SNS Topic 및 Lambda 구성 — `terraform/sns.tf`(`skills-ceh-alert-topic` Standard) + `terraform/lambda.tf`(`skills-ceh-remediate-fn`: python3.12 / `remediate_security_group.lambda_handler` / timeout 30 / env `PROTECTED_SECURITY_GROUP_ID`·`SNS_TOPIC_ARN`) — 실채점 통과: State Active (2026-08-02, 재확인 2026-08-04)
- [x] 3-4 CloudTrail, EventBridge Rule 및 Target 구성 — `terraform/cloudtrail.tf`(`skills-ceh-cloudtrail` enable_logging + S3 버킷/정책) + `terraform/eventbridge.tf`(`skills-ceh-sg-change-rule` default bus, `AuthorizeSecurityGroupIngress` 패턴, Lambda target + `aws_lambda_permission`) — 실채점 통과: IsLogging True / Rule ENABLED (2026-08-02, 재확인 2026-08-04)
- [x] 3-5 최종 기능 검증 — 지급 Lambda 가 Inbound 전체 revoke + SNS 발행. 로그 그룹 `/aws/lambda/skills-ceh-remediate-fn` 은 terraform 선생성. README 검증 1(직접 invoke, 채점과 동일 payload)·검증 2(실경로)로 사전 확인 — 실채점 통과: RESTORED / revokedPermissionCount 1 / SNS_PUBLISHED, poll=1 에 inbound_count=0 (2026-08-02, 재확인 2026-08-04)

### module-4 채점 커버리지 (mark2-4.sh ↔ 구현)
<!-- [x] apply 후 mark2-4.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->

- [x] 4-1 EKS Cluster, VPC, Fargate Profile 구성 — `eksctl/cluster.yaml`: `skills-sqs-cluster`(us-west-2, public+private 엔드포인트) + `terraform/vpc.tf`(private 서브넷, karpenter.sh/discovery 태그) + Fargate profile `skills-sqs-fp-keda`·`skills-sqs-fp-karpenter`(과제지 명시 2개) + `skills-sqs-fp-kube-system`(coredns용 추가) — 실채점 통과: Cluster ACTIVE + Fargate profile 2개 ACTIVE(selector keda/karpenter), CloudShell kubectl 로 fargate 노드 8대 Ready (2026-08-04)
- [x] 4-2 SQS Queue 및 IAM ServiceAccount 구성 — `terraform/sqs.tf`(`skills-sqs-queue`) + `eksctl/cluster.yaml` IRSA `iam.serviceAccounts`(keda-operator/karpenter/sqs-worker-sa 3개, `attachPolicyARNs`로 role-arn annotation 자동 부여) — 실채점 통과: QueueArn 출력 + VisibilityTimeout 30(기준 >=30), SA 3개 role-arn annotation 전부 비어 있지 않음 (2026-08-04)
- [x] 4-3 KEDA/Karpenter Controller Fargate 배포 구성 — `README.md` 4단계 helm install(karpenter -n karpenter, keda -n keda) + Fargate profile 2개로 두 네임스페이스가 Fargate 노드에 스케줄 — 실채점 통과: keda 3개·karpenter 1개 Deployment Available, Pod 전부 Running, NODE 열 전부 `fargate-ip-*` (2026-08-04)
- [x] 4-4 Worker Application 및 KEDA ScaledObject 구성 — `k8s/20-deployment.yaml`(`sqs-worker`, env 3개, nodeSelector 2개) + `k8s/30-keda-scaledobject.yaml`(`sqs-worker-scaledobject`/`sqs-worker-trigger-auth`, min 0/max 6/queueLength 2/pollingInterval 15/cooldownPeriod 30) — 실채점 통과: min 0·max 6 정확, pollingInterval 15(<=15)·cooldownPeriod 30(<=30), trigger `aws-sqs-queue` queueLength "2", TriggerAuthentication 존재 (2026-08-04). 2026-08-07 정정으로 `podIdentity.provider=aws-eks` 판정 기준이 신설되어 `provider`를 `aws`→`aws-eks`로 교체 — 실채점(2026-08-04) 당시 기준에는 없던 항목이라 재검증 미실시
- [x] 4-5 Karpenter NodePool, EC2NodeClass 및 Worker EC2 배치 구성 — `k8s/10-karpenter-nodepool.yaml`(`skills-sqs-nodeclass`/`skills-sqs-nodepool`, label `skills-nodepool=event-worker`, `disruption.consolidationPolicy` 포함) — 실채점 통과: NodePool 4개 필드 + EC2NodeClass `role` 출력. 4-5 조회 시점 노드·파드 0은 정상(min 0) — 라벨 조건은 4-6 의 동일 label selector 출력으로 충족 (2026-08-04)
- [x] 4-6 SQS 기반 Scale Out 및 처리 기능 검증 — ScaledObject queueLength 2 + max 6(12건 발송 시 6 pod) + NodePool 인스턴스 타입 t3.medium/large(500m 요청 pod 다수 스케줄 시 노드 증설 유도) — 실채점 통과: sent=12, after_60s 에 pod 6/6 + Karpenter 노드 2대 Ready(기준 180초), 메시지 12 → after_120s 0 (2026-08-04)

## 함정 절

- **[실측 확인, 2026-08-04] mark2-4.sh 4-5 의 `No resources found` 2줄은 정상 출력이다 — 재배포하지 마라**: 스크립트 97·98행이 Karpenter 노드와 워커 파드를 조회하는데, 채점 시점엔 큐가 비어 있고 `minReplicaCount: 0`이라 둘 다 0이다. 배포 실패가 아니다. 판정 기준이 "min 0으로 채점 직후 Worker Pod가 없을 수 있으므로 ... 4-6 Scale Out 출력 결과를 포함해 판정할 수 있습니다"를 명시하고, 더 결정적으로 **4-6 의 117행이 4-5 의 97행과 완전히 동일한 label selector**(`karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker`)를 쓴다 — 4-6 에서 그 selector 로 노드가 잡히면 라벨 조건이 같은 결과 파일 안에서 증명된다. 이걸 메우겠다고 min 을 올리거나(과제지 6-6 위반) `consolidateAfter` 를 늘려 유휴 노드를 살려두지 마라.
- **[실측 확인, 2026-08-04] `keda-operator` Pod `RESTARTS 1` 은 무해하다**: 생성 직후 1회 재시작한다(2026-08-02 실행엔 없던 값). 4-3 판정 기준은 Deployment Available + Pod Running 만 보므로 무관 — Running 이면 넘어가라. `ApproximateNumberOfMessages` 가 발송 60초 뒤에도 12로 보이는 것도 같은 부류다(SQS 지표 지연, 두 실행 모두 재현). 실제 처리 착수까지 약 57초로 기준 180초 대비 3배 여유다.
- **[실측 확인, 2026-08-02] `.env` 마지막 줄 CRLF로 docker build/push가 깨진다**: PowerShell `Set-Content`가 파일 끝 개행을 CRLF로 써서 `.env` 마지막 줄(`ECR_IMAGE`)에만 `\r`이 붙는다. CloudShell에서 `source .env` 하면 태그가 `...:latest\r`이 돼 build/push가 실패한다. module-4 README 1단계를 `[IO.File]::WriteAllText` + LF 치환으로 고치고, 3단계 `source .env` 앞에 `sed -i 's/\r$//' .env` 가드를 넣었다. mark 스크립트에만 걸려 있던 CRLF 가드로는 이 경로를 못 잡는다.
- **[실측 확인, 2026-08-02] EKS access entry policy ARN은 `arn:aws:eks::aws:...`**: README 7단계에 `arn:aws:eks:aws:cluster-access-policy/...`(콜론 1개)로 적혀 있어 `ResourceNotFoundException`이 났다. 정확한 값은 리전 세그먼트가 빈 `arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy`. `aws eks list-access-policies`로 확인 가능.
- **[실측 확인, 2026-08-02] CloudShell 전송·실행 경로**: 저장소가 private이라 `git clone` 불가(익명 404), 업로드 파일은 항상 `$HOME`에 평면 저장(런북의 `mark/` 경로와 불일치), CloudShell 홈은 리전별로 분리, 이전 세션의 VPC 환경 탭이 활성이면 업로드 메뉴 자체가 비활성. 로컬 대체 실행도 `jq` 부재로 불가 — 채점은 CloudShell 전용이다. 상세는 [FEEDBACK.md](FEEDBACK.md).
- **[실측 확인, 2026-08-02] teardown 두 지점에서 멈춘다**: module-4 `kubectl delete -f rendered/`가 삭제 출력 후에도 종료되지 않아(15분+) 뒤의 helm 단계가 실행되지 않는다 → `--wait=false`. module-2 `terraform destroy` 1회차가 Lattice Target Group Attachment `unexpected state 'UNUSED'`로 실패한다 → 재실행하면 정리된다.
- **service-sg 0.0.0.0/0 → 과제지 명시 미충족 (감점 확정 함정)**: 과제지 4-3이 "0.0.0.0/0 허용 시 미충족"을 명시. `module-2-lattice/terraform/sg.tf`의 service SG는 VPC Lattice managed prefix list 소스만 허용하도록 만들었으나, 30% 변동으로 SG 리소스를 재작성하게 되면 이 조건을 놓치기 쉽다 — service SG ingress에 CIDR 블록을 절대 추가하지 않는다.
- **min 0이라 채점 4-5 시점 pod·노드 0개 — 공식 예상 출력으로 리스크 해소 확정(2026-08-01)**: `sqs-worker-scaledobject`가 minReplicaCount 0(과제지 6-6 요구값)이라 큐가 비어 있으면 4-5 시점에 pod·노드 목록이 비어 보일 수 있다는 우려가 있었다. 공식 예상 출력(`provided/008_chall_2nd_patched_0801.md`) 4-5 판정 기준이 "min 0으로 채점 직후 Worker Pod가 없을 수 있으므로 Worker Pod의 EC2 배치는 4-6 Scale Out 출력 결과를 포함해 판정할 수 있습니다"를 명시 — 감점 리스크가 공식적으로 해소됐고, 우리의 사전 추론(전원 동일 조건이라 감점 성립 불가, 게시판 질의 불필요)도 맞았음이 확인됐다. 런북 8단계는 SQS 재발송이 아니라 **경량 상태 확인**(컨트롤러 pod·CRD 리소스 존재만 조회)으로 축소했다 — 실동작 스모크 테스트는 6단계에서 이미 12건 발송으로 마쳤으므로, 8단계에서 같은 검증을 반복하는 건 과잉이라고 판단(2026-08-01, 사용자 지적).
- **삭제 금지 정책 대비: 이름 충돌 시 삭제 대신 변수 리네임**: 과제지 시행 후 유의사항이 "채점 완료 전 리소스 삭제·수정 금지"다. set-07 module-1의 log group 선존재 충돌은 `aws logs delete-log-group`으로 선삭제하고 재apply해 해결했는데, 대회 규정상 이 삭제 자체가 금지될 수 있다. set-08에서 이름 충돌(예: 기존 리소스 잔존)이 발생하면 삭제를 시도하지 말고 이름 변수(`*_name` 계열)를 리네임해 신규 리소스로 우회하는 경로를 우선한다.
- **CloudShell 업로드 파일 목록**: module-4는 `Dockerfile`(`app/Dockerfile`)·`worker.py`(`provided/module-4/worker.py`)·mark 스크립트(`mark/mark2-4.sh`, module-2는 `mark/mark2-2.sh`)를 CloudShell에 업로드해야 한다. Windows 작업본을 그대로 업로드하면 CRLF가 섞여 bash 스크립트가 깨질 수 있어, 실행 전 `sed -i 's/\r$//' <파일>` 가드가 필요하다(각 모듈 README에 반영됨).
- **CloudShell `.env`는 세션 초기화 시 재업로드 필요**: CloudShell 세션이 끊기면 홈 디렉터리가 초기화되므로 `.env`(module-4 3단계 빌드용) 재업로드가 필요하다. 로컬 `.env.ps1`은 본 PC 재부팅에도 남지만(파일 초기화는 대회 환경 규칙, `.env.ps1`은 gitignore 대상이라 로컬 파일 자체엔 영향 없음) CloudShell 측 파일은 그렇지 않다는 점을 구분한다.
- **helm 차트 미핀 — 대회 당일 차트 기본값 재확인**: KEDA·Karpenter helm 설치에 `--version`을 고정하지 않았다(작업 규칙 2 예외 — eksctl·helm·EKS Addon은 최신 안정). 최신 차트가 `replicas`·`dnsPolicy`·`tolerations` 등의 기본값을 바꾸면 README 4단계 helm 값이 무효화될 수 있어, 대회 당일 실행 전 공식 문서로 현재 기본값을 재확인해야 한다.
- **[module-1] 지급 앱 상수가 변수 변경 폭을 제한한다**: `docdb_client.py`는 region(`ap-northeast-2`)·secret 이름(`skills-nosql-docdb-secret`)·DB 이름(`skills_retail`)·port(27017)를 상수로 박아 둔다. terraform 변수(`region`/`secret_name`/`docdb_port`)만 바꾸면 지급 앱과 어긋나 기능 검증 전체가 실패한다 — 이 변수들은 대회 당일 지급 파일 자체가 바뀐 경우에만 함께 바꾼다.
- **[module-1] TTL 인덱스는 실제로 동작한다 — dataset 만료일 확인**: `sessions.expiresAt`에 TTL(expireAfterSeconds 0)을 걸므로 그 시각(현 dataset 기준 2026-12-01~03)이 지나면 DocumentDB가 문서를 자동 삭제해 sessions count<3 → 채점 1-3·1-4 연쇄 실패. 대회 당일 지급 dataset의 `expiresAt`이 채점 시점보다 미래인지 반드시 확인하고, 과거라면 감독관에게 문의(지급 데이터 결함).
- **[module-3] 실경로 이벤트 지연은 채점 리스크 아님**: CloudTrail→EventBridge 전달은 수 분 걸릴 수 있으나, mark2-3.sh 3-5는 Lambda를 직접 invoke하고 폴링(최대 180초)하므로 실채점은 전달 지연과 무관. 실경로는 README 검증 2로 별도 확인만 한다. 채점 중 mark가 추가한 TCP/22가 실경로 이벤트로 한 번 더 Lambda를 깨워도 IGNORED/NO_ACTION으로 무해.
- **[실측 확인, 2026-08-04] [module-3] 새 Trail 은 apply 직후 EventBridge 로 이벤트를 안 보낸다**: 생성 88초 시점의 authorize 는 TriggeredRules 0·Lambda 미호출, 18분 시점엔 15초 내 복구. 룰·타깃·권한·패턴·셀렉터는 전부 정상이었다. README 검증 2 는 apply 5분 뒤 실행한다(채점 3-5 는 직접 invoke 라 무관).
- **[module-3] trail S3 버킷명은 전역 유일**: `skills-ceh-cloudtrail-<account_id>` 형태로 계정 ID를 붙였다. 그래도 충돌(잔존 버킷 등) 시 삭제 금지 정책에 따라 버킷을 지우지 말고 `trail_name` 변수를 리네임해 우회한다.
- **[협의회 7/31] 당일 변경은 신규 모듈 추가 방향 — 기존 4모듈 재작성 리스크는 낮다**: 2과제 변경은 기존 문제 수정이 아니라 최대 2개 모듈 **추가**(총 6개, 추가 시간 없음)가 원칙. 따라서 기존 4모듈의 30% 변수화는 보험으로 유지하되, 당일 리허설 계획은 "신규 모듈 2개를 처음 보는 상태로 풀 시간"을 남기는 쪽에 무게를 둔다. 세트 선정은 추첨 1인 세트의 4모듈 전체 — 세트가 통째로 나오므로 세트 단위 숙련이 유효하다.
- **[협의회 7/31] PowerUserAccess "수준" + 명시적 Deny 가능**: Deny 의 목적은 사전 제공 리소스 보호이므로 실제로 막히는 건 **기존 리소스의 삭제·수정**이다. 내가 만든 리소스는 대상이 아니다. IAM 생성 자체는 지급 전제(과제지가 이름까지 지정한 Role 을 채점 스크립트가 직접 읽으므로 막히면 채점이 성립 안 함). AccessDenied 가 나면 코드 문제로 단정하지 말고 Deny 정책 여부를 감독관에게 확인한다. "이름 충돌 시 삭제 대신 리네임" 함정과 같은 계열.
- **[협의회 7/31] 채점 중 update-kubeconfig 1회 제한**: 채점 도중 클러스터 접근 불가 시 `aws eks update-kubeconfig` 1회만 허용, 그 외 자격증명 입력·명령 실행 금지. module-4 README 7단계(CloudShell kubeconfig 사전 구성)를 채점 전에 반드시 완료해야 하는 근거.
- **[협의회 7/31] bastion 불필요**: 협의회는 "bastion은 경기 중만 생성·수정하고 채점 명령용만"을 정했으나, set-08 task-2는 CloudShell에서 직접 배포·채점하므로 bastion을 설계상 사용하지 않는다(모듈 terraform/eksctl에 bastion 리소스 없음). 회의 정책 준수.
- **협의회 추적 — 완료(2026-08-01)**: 공식 예상 출력·판정 기준·채점 스크립트 수정 diff가 `provided/008_chall_2nd_patched_0801.md`로 도착. diff는 `mark/mark2-{1..4}.sh`에 적용 완료(결정 로그 참조), 판정 기준은 4모듈 구현·dataset과 전 항목 대조 완료 — 불일치 없음(1-5 기대 데이터도 retail_dataset.json과 일치 확인: O-1001/C001 주문 3건/기간 내 PENDING 3건/W-A low-stock 2건·P-GRN-002 제외). 마이스터넷 오류 정정 마감 **2026-08-13** — 추가 오류 발견 시 그 전에 게시판 질의(72시간 내 답변 원칙).
- **NodePool/EC2NodeClass의 subnet·SG selector 태그 값은 치환 범위 밖 리터럴**: `k8s/10-karpenter-nodepool.yaml`의 `subnetSelectorTerms`(`karpenter.sh/discovery: "skills-sqs-cluster"`)와 `securityGroupSelectorTerms`(`aws:eks:cluster-name: "skills-sqs-cluster"`)는 README 렌더링 단계의 치환 placeholder가 아니라 클러스터 이름을 직접 박은 리터럴이다. `terraform/variables.tf`의 `var.cluster_name`이나 `eksctl/cluster.yaml`의 `metadata.name`을 바꾸면(30% 변동 대비) 이 두 태그 값도 함께 수동으로 맞춰야 한다 — 놓치면 Karpenter가 서브넷·SG를 디스커버리하지 못해 노드 프로비저닝 자체가 실패한다.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

2026-08-02 실 apply·실채점 리허설로 전부 실측치로 교체했다. 원본 로그는 [LOGS.md](LOGS.md).

- module-1 apply: 22 added / **~7분** (DocumentDB instance 병목, 기존 10-15분 예상은 과대)
- module-2 apply: 24 added / ~2분
- module-3 apply: 16 added / ~1분
- module-4 apply: 30 added / ~3분 (NAT GW 병목)
- 공통 병목: eksctl 클러스터 생성 **19분** (삭제는 8분) — CloudShell 이미지 빌드/push(~2분)와 병렬 처리 설계(README 3단계)
- helm karpenter+keda: ~2분 / module-4 scale out(12건→pod 6+노드 2): 60초 이내 / scale in: 큐 소진 후 ~3분
- module-3 실경로 복구(CloudTrail→EventBridge→Lambda): **19.6초** (기준 180초, "수 분" 상정보다 훨씬 빠름)
- 채점 스크립트: mark2-1/2/3 각 1~3분, **mark2-4는 ~11분**(CloudShell kubectl 설치 + 4-6의 sleep 60×3)

---
## 정정 로그
<!-- 과제지·채점지 정정과 그에 따른 구현 변경. 질의일·답변일·출처를 함께 적는다. 최신이 위로. -->

### 2026-08-12 [module-4] 4-5 min 0 예외 판정 범위가 Node 까지 확대
- 출처: `provided/20260812_CHANGELOG.md` (답변일 2026-08-12). 대응 PATCH 파일 없음
- 내용: 0809 판정 기준은 "Pod 가 없을 경우 4-6 결과를 포함해 판정"이었으나, 0812 는 "Worker EC2 **Node 또는** Worker Pod 가 없을 수 있으므로"로 예외 범위를 노드까지 넓혔다. 4-5 는 **0812 가 판정 기준 최종본**, 채점 명령은 0809 PATCH 적용본이 최종이다(0812 는 스크립트를 건드리지 않음)
- 판정: **영향없음** — 구제 범위 확대라 구현 요구가 늘지 않는다. `k8s/10-karpenter-nodepool.yaml`(consolidationPolicy `WhenEmpty`/30s)로 채점 시점에 노드가 비어 있을 수 있는 상황 자체는 종전과 동일

### 2026-08-09 [module-4] 4-5 노드 조회에 nodepool/skillsNodepool 라벨 출력 추가
- 출처: `provided/20260809_PATCH.patch`·`20260809_CHANGELOG.md` (답변일 2026-08-09)
- 판정: **수정완료(채점 스크립트만)** — `mark/mark2-4.sh` 4-5 노드 조회를 패치본 jq 로 교체. 구현은 `k8s/10-karpenter-nodepool.yaml`의 `spec.template.metadata.labels`에 `skills-nodepool: event-worker`가 이미 있어 Karpenter 가 노드에 두 라벨을 모두 부여한다 — 구현 변경 없음

### 2026-08-07 [module-4] 4-4 podIdentity.provider 판정 기준 신설 (aws → aws-eks)
- 출처: `provided/20260807_CHANGELOG.md` (답변일 2026-08-07)
- 내용: 0801 판정 기준은 TriggerAuthentication 의 존재만 봤으나, 0807 이 `podIdentity.provider=aws-eks이어야 합니다`를 새로 넣었다
- 판정: **수정완료** — `k8s/30-keda-scaledobject.yaml` `provider: aws` → `aws-eks`. 아래 2026-08-01 결정(`aws` 채택)을 채점 기준 우선 원칙(CLAUDE.md 작업규칙 4)으로 번복한다
- 확인: KEDA 공식 문서상 `aws-eks`는 deprecated 이나 제거는 v3 예정이고 최신 문서가 2.20 이라 설치 버전(helm 최신)에서 여전히 유효하다. deprecated 경고만 뜬다

### 2026-08-07 [module-4] 4-1/4-3/4-4/4-5 채점 조회 축소, [module-2] 2-2/2-3/2-5 변수명·출력
- 출처: `provided/20260807_PATCH.patch`·`20260807_CHANGELOG.md` (답변일 2026-08-07)
- 판정: **수정완료(채점 스크립트만)** — `mark/mark2-2.sh`(`CLIENT_IP`→`LATTICE_CLIENT_EC2_PUBLIC_IP`, `VPC_ASSOCIATION_ID` echo 추가), `mark/mark2-4.sh`(4-1 Version·Role 제거 + Namespaces·노드 이름만, 4-3 Deployment 고정 조회, 4-4 TriggerAuthentication 3필드, 4-5 jq 최소 출력)
- 구현 영향 없음: 4-1 에서 `Version` 이 빠져 **EKS 버전은 풀이자 지정**으로 확정 — `eksctl/cluster.yaml`의 현재 버전을 그대로 둔다. 4-3 이 Deployment 이름을 `keda-operator`/`karpenter`로 고정 조회하므로 helm release 이름을 바꾸면 안 된다(README 4단계 그대로 유지)

### 2026-08-07 [module-2] 2-4 Service EC2 SG 8080 인바운드 재확인
- 출처: `provided/20260807_CHANGELOG.md` 판정 기준 (변경이 아닌 재기재)
- 판정: **영향없음** — `terraform/sg.tf`가 `prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id]`만 두고 `cidr_blocks`를 쓰지 않아 `0.0.0.0/0` 허용이 없다

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

### 2026-08-17 [module-4] CloudShell 3단계 업로드를 zip 1개로 전환
- 맥락: 3단계(worker 이미지 build/push)가 `app/Dockerfile`·`provided/module-4/worker.py`·`.env` 3개를 CloudShell에 개별 업로드했다 — 파일 하나 빠뜨리거나 다른 리전 탭에서 업로드하면 build 시점에야 실패가 드러난다
- 채택: 본 PC에서 `Compress-Archive`로 3개 파일을 module 홈폴더(`module-4-sqs-scaling/`)에 `m4.zip`으로 묶고, CloudShell엔 zip 하나만 업로드 후 `unzip -oj`로 홈에 풀어 진행. 모듈별 zip은 `mN.zip`(module-N)으로 통일 — CloudShell에서 타이핑 짧게. `.gitignore`에 패턴 추가(`**/m[0-9].zip`)해 커밋 방지
- 기각: 개별 3파일 업로드 유지 → 업로드 누락·오탭 위험이 여전
- 대가: 없음 (unzip은 CloudShell 기본 제공)

### 2026-08-01 [공통] 공식 채점 스크립트 수정 diff를 mark/에 적용
- 맥락: 협의회가 예고한 공식 예상 출력 파일(`008_chall_2nd_patched_0801.md`)이 도착 — 판정 기준 전문 + 채점 스크립트 4개의 수정 diff(CloudShell 도구 자동 설치 헤더, module-4는 조회를 yaml 덤프에서 jq 필드 추출로 교체, 4-6 메시지 body `judge-N` 고정) 포함. 출제 측은 원본 파일을 직접 수정하지 않고 정정본을 별도 배포하는 방식
- 채택: 공식 문서 원본은 `provided/008_chall_2nd_patched_0801.md`에 무수정 보존하고, diff는 `mark/mark2-{1..4}.sh`에 적용 — mark/는 "대회에서 실제 실행될 채점 스크립트"를 항상 반영한다는 원칙. `bash -n` 문법 검증 통과
- 기각: mark/를 구버전 원본 그대로 두고 패치본을 별도 파일로 병존 → 셀프 채점이 실제 채점과 어긋난 채 진행될 위험, 런북의 mark 실행 경로도 두 갈래가 됨
- 대가: mark/가 더 이상 "최초 배포본과 diff 없음" 상태가 아님 — 원본 대조가 필요하면 provided/의 공식 문서와 git 이력으로 추적

### 2026-08-01 [module-3] EventBridge 패턴 최소화 — groupId 필터 미포함
- 맥락: rule 이 모든 `AuthorizeSecurityGroupIngress` 를 잡으면 보호 SG 외 이벤트에도 Lambda 가 호출된다
- 채택: 과제지 5-4 문구 그대로 source/detail-type/eventName 매칭만. 보호 SG 여부 판별은 지급 Lambda 의 IGNORED 로직에 위임
- 기각: `detail.requestParameters.groupId` 필터 추가 → CloudTrail 이벤트의 groupId 위치가 요청 형태에 따라 달라(단건/중첩) 매칭 누락 위험이 있고 과제지 무요구
- 대가: 무관 SG 이벤트에도 Lambda 호출 발생 (IGNORED 로 무해, 비용 무시 가능)

### 2026-08-01 [module-3] EC2 는 IGW 없는 최소 VPC 구성
- 맥락: 채점 3-1 은 EC2 존재·protected SG 연결만 확인하고 외부 접근 요구가 없다
- 채택: 서브넷 1개, IGW·Public IP 미생성. protected SG 는 ingress 리소스 자체를 선언하지 않아 Inbound 0개(채점 3-2)가 기본 상태이고, 채점 3-5 가 임시 추가하는 규칙도 state 밖이라 drift 가 없다
- 기각: public 서브넷 + IGW → 접근할 일이 없는 미사용 리소스 (리뷰 규칙: 미사용 정리)
- 대가: EC2 에 SSM/SSH 접근 불가 — 접근 필요 자체가 없어 무해

### 2026-08-01 [module-1] 인덱스·TTL 생성을 별도 index_setup.py 로 분리
- 맥락: 과제지 3-3 의 인덱스 8종(TTL 포함)은 지급 `docdb_client.py` 에 생성 코드가 없다(조회·나열만). 지급 앱은 수정 금지
- 채택: `terraform/index_setup.py.tftpl`(region·secret 이름은 terraform 변수 치환, `create_index` 멱등)을 user-data 로 EC2 에 배치해 seed 직후 실행
- 기각: (a) 지급 앱에 생성 코드 추가 → 수정 금지 위반. (b) CloudShell/로컬에서 mongosh 수동 실행 → DocumentDB 가 외부 비노출이라 도달 불가하고 수동 단계만 추가
- 대가: 없음

### 2026-08-01 [module-1] user-data 임베드를 base64gzip 으로 전환
- 맥락: 지급 `docdb_client.py`(9KB) + `retail_dataset.json`(5KB) 을 module-2 식 평문 base64 로 임베드하면 EC2 user-data 16KB 한도를 초과한다
- 채택: terraform `base64gzip()` + 부팅 시 `base64 -d | gunzip` — 총 user-data ~7KB
- 기각: S3 스테이징 버킷 경유 다운로드 → 버킷·IAM 권한·업로드 순서가 추가되는 과제지 무요구 리소스
- 대가: user-data 원문 가독성 저하 (스크립트 원본은 템플릿 파일로 저장소에 남아 무해)

### 2026-08-01 [module-4] eksctl/k8s ARN·role 플레이스홀더를 terraform output 직접 소비로 전환 (fix-wave)
- 맥락: `eksctl/cluster.yaml`의 attachPolicyARNs 3개·accessEntries principalARN, `k8s/10-karpenter-nodepool.yaml`의 EC2NodeClass `role`이 모두 `arn:aws:iam::${ACCOUNT_ID}:policy/skills-sqs-*` 또는 `KarpenterNodeRole-skills-sqs-cluster` 형태로 ARN·이름을 리터럴 재조립하고 있었다. 이름 변수(`name_prefix`·`cluster_name`)가 대회 당일 바뀌면(30% 변동) 이 재조립 문자열들이 개별적으로 어긋나 eksctl 후반부(IRSA·access entry)나 Karpenter 노드 조인이 조용히 실패할 위험이 있었다
- 채택: 4개 ARN·1개 role 값을 각각 `${KEDA_POLICY_ARN}`/`${KARPENTER_POLICY_ARN}`/`${WORKER_POLICY_ARN}`/`${NODE_ROLE_ARN}`(cluster.yaml)와 `${NODE_ROLE_NAME}`(k8s)로 바꾸고, terraform output(`keda_policy_arn`/`karpenter_policy_arn`/`worker_policy_arn`/`karpenter_node_role_arn`/`karpenter_node_role_name`)을 README 렌더링 단계에서 그대로 주입 — 이름이 바뀌어도 terraform이 계산한 실제 ARN을 그대로 쓰므로 치환 체인이 끊기지 않는다. `${ACCOUNT_ID}` 재조립은 cluster.yaml에서 완전히 제거(다른 곳에 남지 않아 README 치환 목록에서도 제거, 단 CloudShell ECR 로그인용 `ACCOUNT_ID` 자체는 유지)
- 기각: 이름 변수 변경 시 cluster.yaml·k8s manifest를 수동으로 같이 고치는 규약 → 이미 set-07부터 반복된 "이름 변경 시 후속 파일 갱신 누락" 함정과 동일 패턴이라 재발 방지 차원에서 구조적으로 없앰
- 대가: 없음 (terraform output이 이미 이 값들을 노출하고 있어 추가 리소스·API 호출 없음)

### 2026-08-01 [module-2] Service EC2 Public IP 요구 오독 정정 (fix-wave)
- 맥락: 최초 설계에서 "채점 mark2-2.sh가 PublicIp 필드를 확인한다"를 "두 인스턴스 모두 Public IP가 있어야 한다"로 잘못 해석해 `vpc.tf`의 service 서브넷도 `map_public_ip_on_launch = true`로 만들었다. 그러나 과제지가 "Client EC2는 Public IP로 HTTP 접근 가능해야 하며, Service EC2는 Public IP 없이 내부 서비스로 구성합니다"(task.md:117)를 명시하고 있었고, mark2-2.sh는 PublicIp 필드를 단순 조회·출력할 뿐 값의 존재를 요구하지 않는다
- 채택: service 서브넷의 `map_public_ip_on_launch`를 `false`로 정정. client 서브넷은 그대로 유지(Public IP 필요, 과제지 명시). service 서브넷의 IGW 라우트는 그대로 남기되 Public IP 자체가 없어 무해(Lattice 데이터 플레인이 Target Group을 통해 서비스 VPC 내부에서 직접 인스턴스에 도달하므로 IGW 경로에 의존하지 않음)
- 기각: service 서브넷을 완전한 private 서브넷(라우트 테이블에서 IGW 라우트 제거)으로 재구성 → 과제지가 요구하는 것은 Public IP 미할당이지 라우트 제거가 아니며, 라우트 제거는 SG가 이미 담당하는 차단을 중복 구현하는 것이라 최소 변경 원칙에 어긋남
- 대가: 없음 (기능·채점 영향 없음 — client→service 경로는 Lattice 데이터 플레인만 사용)

### 2026-08-01 [module-4] Fargate 컨트롤러 + skills-sqs-fp-kube-system 추가, coredns addon configurationValues computeType=Fargate
- 맥락: 과제지 6-2가 Fargate Profile 2개(`skills-sqs-fp-keda`·`skills-sqs-fp-karpenter`)만 명시. 그러나 워커는 Karpenter EC2 노드여야 하고(과제지 6-1·6-5), 클러스터에 Managed NodeGroup을 두지 않는 이상 CoreDNS가 스케줄될 노드 자체가 없다
- 채택: coredns EKS addon `configurationValues: {"computeType": "Fargate"}` + kube-system 전용 Fargate profile(`skills-sqs-fp-kube-system`)을 추가로 선언 — CoreDNS를 Fargate에 태운다. 채점 4-1은 명시된 2개 profile의 존재만 검사하므로 추가 profile은 감점 요인이 아니다
- 기각: 소형 Managed NodeGroup(t3.small 1대 등)을 추가해 CoreDNS를 그곳에 배치 → 과제지가 "Worker Pod는 Fargate가 아닌 Karpenter EC2 Worker Node에서 실행"(6-5)만 요구할 뿐 시스템 컴포넌트용 NodeGroup은 요구하지 않음 — 문제지 외 최대 리소스를 만들게 됨
- 대가: 없음 (Fargate CoreDNS는 EKS 공식 지원 경로)

### 2026-08-01 [module-4] TriggerAuthentication podIdentity.provider aws
- 맥락: KEDA ScaledObject가 AWS SQS 트리거 인증을 받아야 한다(과제지 6-6). set-07의 module-3 결정 로그(2026-07-26)는 `identityOwner: operator` 방식을 채택했으나 그 결정 자체가 "KEDA 3.0에서 제거 예정(deprecated)"이라는 대가를 남겼다
- 채택: `TriggerAuthentication.spec.podIdentity.provider: aws` — keda-operator SA의 IRSA 역할을 그대로 사용하는 현재 KEDA 권장 경로. set-07이 예고한 "차기 세트에서 TriggerAuthentication 전환 검토"를 이번 세트에서 실행
- 기각: `identityOwner: operator` 계승 → 이미 deprecated 표시된 경로를 신규 구현에 다시 쓰는 것은 불필요한 기술 부채
- 대가: 없음 (같은 IRSA SA를 참조하는 동일한 결과)

### 2026-08-01 [module-4] pollingInterval 15 유지 — minReplicaCount 0이라 0→1 활성화에 유효
- 맥락: set-07 module-3의 2026-07-31 결정 로그는 `pollingInterval`을 삭제했다 — 그 근거는 "minReplicaCount≥1이면 0→1 전환이 없어 pollingInterval이 완전 무효"였다. 이번 ScaledObject(`sqs-worker-scaledobject`)는 `minReplicaCount: 0`으로 그 전제 자체가 다르다
- 채택: `pollingInterval: 15` 유지 — min=0/idleReplicaCount 상태에서 0→1 활성화는 KEDA operator의 직접 폴링(pollingInterval)에 의존하므로 이 필드가 실제로 유효하다. 과제지 상한(15초 이하)도 그대로 충족
- 기각: set-07 선례를 그대로 따라 필드 삭제 → min=0 스케일에서는 활성화 감지 주기가 없어져 최초 스케일아웃 지연이 불명확해짐
- 대가: 없음. set-07의 삭제 결정은 min=1 전제였음을 여기서 명시적으로 뒤집는다 — 두 결정이 상충하는 것처럼 보이나 전제 조건이 다르므로 둘 다 유효

### 2026-08-01 [module-4] consolidationPolicy WhenEmpty/consolidateAfter 30s
- 맥락: 과제지 6-7은 NodePool에 `spec.disruption.consolidationPolicy` 설정이 "포함"되어 있을 것만 요구하고 구체적 정책값·시간은 지정하지 않는다
- 채택: `WhenEmpty` + `consolidateAfter: 30s` — min 0 스케일(4-6/4-5) 설계상 큐 소진 후 워커 pod가 0으로 줄면 빈 노드를 최대한 빨리 반환하는 것이 목적에 부합. 값 자체가 채점 대상이 아니라 존재 여부만 필요
- 기각: `WhenEmptyOrUnderutilized` → 노드가 완전히 비지 않아도 재배치를 시도해 부하 테스트(4-6) 도중 워커 pod가 예기치 않게 옮겨질 여지가 생김. 과제지가 값을 지정하지 않은 상황에서 굳이 더 공격적인 정책을 택할 이유가 없음
- 대가: 없음

### 2026-08-01 [module-4] Karpenter helm dnsPolicy=Default
- 맥락: Karpenter 컨트롤러가 Fargate profile(`skills-sqs-fp-karpenter`)에서 기동한다. Fargate 기동 초기에는 CoreDNS(이 또한 Fargate 위)가 아직 준비되지 않았을 수 있어, 기본 `dnsPolicy: ClusterFirst`로는 컨트롤러가 자신이 의존하는 CoreDNS의 기동을 기다리는 순환 의존이 생길 수 있다
- 채택: helm `--set dnsPolicy=Default` — 파드 네트워크 네임스페이스가 노드(Fargate)의 DNS 설정(VPC 리졸버)을 그대로 사용해 CoreDNS 경유 없이 이름 해석
- 기각: 기본값 `ClusterFirst` 유지 → CoreDNS 기동 순서에 Karpenter 컨트롤러 준비가 종속되는 리스크를 그대로 안음
- 대가: 없음 (Karpenter 컨트롤러는 K8s 서비스 이름을 조회할 필요가 없어 DNS 정책 완화의 부작용 없음)

### 2026-08-01 [module-2] SERVICE_URL terraform 참조 주입
- 맥락: client EC2의 `client_app.py`는 `SERVICE_URL` 환경변수로 VPC Lattice service의 generated domain을 알아야 한다(과제지 4-2). 이 도메인은 `aws_vpclattice_service.order` 생성 후에만 확정된다
- 채택: client 인스턴스 user-data(`userdata-client.sh.tftpl`)에 `service_url = "http://${aws_vpclattice_service.order.dns_entry[0].domain_name}"`를 terraform 참조로 직접 주입 — 리소스 의존 그래프가 순서를 자동 보장
- 기각: apply 후 도메인 값을 수동 조회해 EC2에 SSH/SSM으로 치환 → 배포 순서를 사람이 관리해야 하는 의존성이 추가됨
- 대가: `aws_vpclattice_service.order`의 도메인이 바뀌는 변경(예: 서비스 재생성)이 있으면 client 인스턴스의 user_data가 바뀌어 인스턴스가 재생성된다

### 2026-08-01 [module-2] service-sg prefix list 소스만
- 맥락: 과제지 4-3이 "TCP/8080은 VPC Lattice Managed Prefix List 소스만 허용하며, 0.0.0.0/0 허용 시 미충족"을 명시
- 채택: `terraform/sg.tf`의 service SG ingress를 `data.aws_ec2_managed_prefix_list.vpc_lattice`(`com.amazonaws.<region>.vpc-lattice`) 단일 소스로 한정
- 기각: `0.0.0.0/0` → 과제지 명시 미충족으로 확정 감점
- 대가: 없음 (Target Group이 Lattice 데이터 플레인을 통해서만 도달하므로 기능 제약 없음)

### 2026-08-01 [module-2] SN-VPC association client VPC만
- 맥락: 과제지 4-4는 Service Network의 VPC Association을 Client VPC(`skills-lattice-client-vpc`)에 대해서만 명시한다. Service VPC 연결 여부는 명시가 없다
- 채택: `aws_vpclattice_service_network_vpc_association`을 client VPC 하나만 생성 — Target Group이 `config.vpc_identifier`로 Service VPC를 직접 참조하므로 target 인스턴스 등록·헬스체크에 Service VPC의 SN 연결이 불필요
- 기각: Service VPC도 SN에 추가로 연결 → 과제지 미요구 리소스이며, TG의 vpc_identifier 경로로 이미 target에 도달 가능해 중복
- 대가: 없음

### 2026-08-02 [공통] IAM 권한 프로브 철회 (아래 08-01 결정 번복)
- 맥락: 프로브는 `skills-iam-probe` role 을 만들었다 지우는 방식이었는데, 협의회가 말한 Deny 는 **사전 제공 리소스 보호**용이다. 내가 방금 만든 role 은 애초에 그 Deny 의 대상이 아니라 프로브가 통과해도 아무것도 검증되지 않는다. "IAM 전면 미지급" 가정도 과했다 — 과제지가 이름을 지정한 Role(`unicorn-audit-role` 등)을 채점 스크립트가 직접 읽으므로 IAM 이 막힌 계정을 지급하면 채점 자체가 성립하지 않는다
- 채택: 프로브 전면 삭제(module-1~4 README·README.linux, task-2 README 실행 순서, docs runbook). module-4 0단계는 CloudShell 접속 확인만 남긴다 — 이건 실제로 막히면 이미지 build/push 경로가 통째로 끊기는 진짜 선행 조건
- 기각: `attach-role-policy`·`PassRole` 까지 넓힌 강화 프로브 → 검사 대상이 위험 지점이 아니라는 문제가 그대로다. 범위를 넓혀도 Deny 는 여전히 안 건드린다
- 대가: IAM 이 정말 막힌 계정이면 첫 apply 에서 발견한다. 확률이 낮고, 발견 후 대응(감독관 문의)은 프로브로 알았을 때와 동일하므로 손실 없음. 실제 Deny 리스크 대비책은 기존 "이름 충돌 시 삭제 금지·리네임 우회" 규칙이 담당

### 2026-08-01 [공통] IAM 생성 권한 지급 전제 + 런북 0단계 프로브 (2026-08-02 철회)
- 맥락: 협의회 확인 결과 대회 계정 IAM 권한 수준은 "PowerUser 이상"으로 전제된다. module-1(nosql은 Secrets Manager·KMS 정책 필요), module-3(Lambda 실행 롤), module-4(IRSA 롤·정책 3종, KarpenterNodeRole)는 모두 IAM 리소스 생성 권한이 없으면 성립 자체가 불가능하다
- 채택: `module-4-sqs-scaling/README.md` 0단계에 IAM role 생성→즉시 삭제 프로브(`skills-iam-probe`)를 넣어 대회 시작 직후 1회 실행 — AccessDenied 시 즉시 감독관에게 문의할 수 있게 조기 실패시킨다. module-2는 IAM 리소스가 없어 프로브를 module-4 런북으로 위임(README에 링크만)
- 기각: 프로브 없이 각 모듈 apply 중간에 실패를 만나는 방식 → 실패 시점이 늦어 대응 시간(4시간 제한)을 낭비
- 대가: 프로브 자체가 role 생성·삭제 API 호출 2회를 추가로 소비 (무료, 무시 가능)
