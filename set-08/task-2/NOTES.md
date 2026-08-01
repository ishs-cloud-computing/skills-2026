# set-08 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 4개 고정. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 리전 | 채점 커버 | 미해결 |
|------|------|------|-----------|--------|
| 1 | nosql | ap-northeast-2 | 0/5 | 미착수 |
| 2 | lattice | ap-northeast-1 | 5/5 (`[~]` plan 수준 검증, 실채점 미실행) | 없음 |
| 3 | event-handling | ap-southeast-1 | 0/5 | 미착수 |
| 4 | sqs-scaling | us-west-2 | 6/6 (`[~]` plan 수준 검증, 실채점 미실행) | 없음 |

module-2·module-4는 terraform/eksctl/k8s/runbook까지 구현 완료했으나 자격증명이 있는 로컬에서 `terraform plan`만 실행했다(module-2 24 add, module-4 30 add, 둘 다 0 errors). apply 이후 CloudShell `mark2-2.sh`·`mark2-4.sh` 실채점은 아직 수행하지 않았다 — 아래 커버리지 표의 `[~]`는 전부 이 수준을 의미한다.

### module-2 채점 커버리지 (mark2-2.sh ↔ 구현)
<!-- [x] apply 후 mark2-2.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->

- [~] 2-1 기본 VPC 구성 — `terraform/vpc.tf`: Client VPC(`skills-lattice-client-vpc` 10.61.0.0/16)·Service VPC(`skills-lattice-service-vpc` 10.62.0.0/16) + public 서브넷 각 1개, peering/TGW 없음
- [~] 2-2 Client/Service EC2 및 애플리케이션 구성 — `terraform/ec2.tf`: `provided/module-2/{client_app.py,service_app.py}` 무수정 base64 user-data, client는 Public IP(:80)·service는 Public IP 없이 서비스 VPC 내부(:8080)
- [~] 2-3 VPC Lattice Service Network 및 Service 구성 — `terraform/lattice.tf`: `aws_vpclattice_service_network.this`(name=`skills-lattice-sn`) + `aws_vpclattice_service.order`(name=`skills-lattice-order-service`, dns_entry 노출) + SN-Service association
- [~] 2-4 Target Group, Listener, Security Group 구성 — `terraform/lattice.tf`의 `aws_vpclattice_target_group.order`(INSTANCE, HTTP/8080, health check `/health`) + `aws_vpclattice_listener.http`(HTTP/80→TG forward) + `terraform/sg.tf`의 service SG(prefix list 소스만)
- [~] 2-5 End-to-End 기능 검증 — `ec2.tf`의 client user-data가 `SERVICE_URL`을 `aws_vpclattice_service.order.dns_entry[0].domain_name`으로 terraform 참조 주입 → `client_app.py`가 `/v1/client/orders?id=1001` 호출 시 Lattice 경유로 `service_app.py`에 도달

### module-4 채점 커버리지 (mark2-4.sh ↔ 구현)
<!-- [x] apply 후 mark2-4.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->

- [~] 4-1 EKS Cluster, VPC, Fargate Profile 구성 — `eksctl/cluster.yaml`: `skills-sqs-cluster`(us-west-2, public+private 엔드포인트) + `terraform/vpc.tf`(private 서브넷, karpenter.sh/discovery 태그) + Fargate profile `skills-sqs-fp-keda`·`skills-sqs-fp-karpenter`(과제지 명시 2개) + `skills-sqs-fp-kube-system`(coredns용 추가)
- [~] 4-2 SQS Queue 및 IAM ServiceAccount 구성 — `terraform/sqs.tf`(`skills-sqs-queue`) + `eksctl/cluster.yaml` IRSA `iam.serviceAccounts`(keda-operator/karpenter/sqs-worker-sa 3개, `attachPolicyARNs`로 role-arn annotation 자동 부여)
- [~] 4-3 KEDA/Karpenter Controller Fargate 배포 구성 — `README.md` 4단계 helm install(karpenter -n karpenter, keda -n keda) + Fargate profile 2개로 두 네임스페이스가 Fargate 노드에 스케줄
- [~] 4-4 Worker Application 및 KEDA ScaledObject 구성 — `k8s/20-deployment.yaml`(`sqs-worker`, env 3개, nodeSelector 2개) + `k8s/30-keda-scaledobject.yaml`(`sqs-worker-scaledobject`/`sqs-worker-trigger-auth`, min 0/max 6/queueLength 2/pollingInterval 15/cooldownPeriod 30)
- [~] 4-5 Karpenter NodePool, EC2NodeClass 및 Worker EC2 배치 구성 — `k8s/10-karpenter-nodepool.yaml`(`skills-sqs-nodeclass`/`skills-sqs-nodepool`, label `skills-nodepool=event-worker`, `disruption.consolidationPolicy` 포함)
- [~] 4-6 SQS 기반 Scale Out 및 처리 기능 검증 — ScaledObject queueLength 2 + max 6(12건 발송 시 6 pod) + NodePool 인스턴스 타입 t3.medium/large(500m 요청 pod 다수 스케줄 시 노드 증설 유도)

## 함정 절

- **service-sg 0.0.0.0/0 → 과제지 명시 미충족 (감점 확정 함정)**: 과제지 4-3이 "0.0.0.0/0 허용 시 미충족"을 명시. `module-2-lattice/terraform/sg.tf`의 service SG는 VPC Lattice managed prefix list 소스만 허용하도록 만들었으나, 30% 변동으로 SG 리소스를 재작성하게 되면 이 조건을 놓치기 쉽다 — service SG ingress에 CIDR 블록을 절대 추가하지 않는다.
- **min 0이라 채점 4-5 시점 pod·노드 0개 가능**: `sqs-worker-scaledobject`가 minReplicaCount 0이라 큐가 비어 있으면 pod·Karpenter 노드가 0개인 상태가 정상이다. mark2-4.sh는 항목 순서상 4-5(NodePool·배치 확인)가 4-6(scale-out 검증) *이전에* 실행되므로, 4-5 시점에 리소스가 조회되지 않아도 실패가 아니다 — 4-6에서 부하를 발생시킨 뒤 노드·pod가 실제로 뜨는 경로를 재확인해야 4-5의 정합성을 판단할 수 있다.
- **삭제 금지 정책 대비: 이름 충돌 시 삭제 대신 변수 리네임**: 과제지 시행 후 유의사항이 "채점 완료 전 리소스 삭제·수정 금지"다. set-07 module-1의 log group 선존재 충돌은 `aws logs delete-log-group`으로 선삭제하고 재apply해 해결했는데, 대회 규정상 이 삭제 자체가 금지될 수 있다. set-08에서 이름 충돌(예: 기존 리소스 잔존)이 발생하면 삭제를 시도하지 말고 이름 변수(`*_name` 계열)를 리네임해 신규 리소스로 우회하는 경로를 우선한다.
- **CloudShell 업로드 파일 목록**: module-4는 `Dockerfile`(`app/Dockerfile`)·`worker.py`(`provided/module-4/worker.py`)·mark 스크립트(`mark/mark2-4.sh`, module-2는 `mark/mark2-2.sh`)를 CloudShell에 업로드해야 한다. Windows 작업본을 그대로 업로드하면 CRLF가 섞여 bash 스크립트가 깨질 수 있어, 실행 전 `sed -i 's/\r$//' <파일>` 가드가 필요하다(각 모듈 README에 반영됨).
- **CloudShell `.env`는 세션 초기화 시 재업로드 필요**: CloudShell 세션이 끊기면 홈 디렉터리가 초기화되므로 `.env`(module-4 3단계 빌드용) 재업로드가 필요하다. 로컬 `.env.ps1`은 본 PC 재부팅에도 남지만(파일 초기화는 대회 환경 규칙, `.env.ps1`은 gitignore 대상이라 로컬 파일 자체엔 영향 없음) CloudShell 측 파일은 그렇지 않다는 점을 구분한다.
- **helm 차트 미핀 — 대회 당일 차트 기본값 재확인**: KEDA·Karpenter helm 설치에 `--version`을 고정하지 않았다(작업 규칙 2 예외 — eksctl·helm·EKS Addon은 최신 안정). 최신 차트가 `replicas`·`dnsPolicy`·`tolerations` 등의 기본값을 바꾸면 README 4단계 helm 값이 무효화될 수 있어, 대회 당일 실행 전 공식 문서로 현재 기본값을 재확인해야 한다.
- **협의회 추적**: 공식 예상 출력 파일(mark.md 원본) 도착 시 이 표와 `mark/mark2-*.sh` 실제 검사 항목을 다시 대조한다.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

- module-1 apply:
- module-2 apply: terraform plan 실측 24 add / 0 errors (apply 미실행)
- module-3 apply:
- module-4 apply: terraform plan 실측 30 add / 0 errors (apply 미실행)
- 공통 병목: EKS 클러스터 생성(eksctl, module-4) ~15-20분 예상 — CloudShell 이미지 빌드/push와 병렬 처리 설계(README 3단계)

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

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

### 2026-08-01 [공통] IAM 생성 권한 지급 전제 + 런북 0단계 프로브
- 맥락: 협의회 확인 결과 대회 계정 IAM 권한 수준은 "PowerUser 이상"으로 전제된다. module-1(nosql은 Secrets Manager·KMS 정책 필요), module-3(Lambda 실행 롤), module-4(IRSA 롤·정책 3종, KarpenterNodeRole)는 모두 IAM 리소스 생성 권한이 없으면 성립 자체가 불가능하다
- 채택: `module-4-sqs-scaling/README.md` 0단계에 IAM role 생성→즉시 삭제 프로브(`skills-iam-probe`)를 넣어 대회 시작 직후 1회 실행 — AccessDenied 시 즉시 감독관에게 문의할 수 있게 조기 실패시킨다. module-2는 IAM 리소스가 없어 프로브를 module-4 런북으로 위임(README에 링크만)
- 기각: 프로브 없이 각 모듈 apply 중간에 실패를 만나는 방식 → 실패 시점이 늦어 대응 시간(4시간 제한)을 낭비
- 대가: 프로브 자체가 role 생성·삭제 API 호출 2회를 추가로 소비 (무료, 무시 가능)
