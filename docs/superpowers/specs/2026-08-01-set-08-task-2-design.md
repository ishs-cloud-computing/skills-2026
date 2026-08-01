# set-08 task-2 설계 (모듈 2·4 우선)

- 날짜: 2026-08-01
- 브랜치: `set-08/task-2`
- 자료: `C:\Users\User\Downloads\national-skills-v7\2과제\` (문제지·채점지 PDF, 모듈별 check 스크립트·지급파일)
- 이번 범위: 스캐폴드 + task.md/mark.md 변환 + **module-2(VPC Lattice)·module-4(SQS/EKS)** 구현. 모듈 1·3은 다음 세션.
- 검증 깊이: `terraform fmt`·`validate`·`plan`까지. 실 apply·실채점은 다음 세션.

## 1. 과제 개요

2과제 = 독립 Small Challenge 4개, 리전 4개.

| 모듈 | 이름 | 내용 | 리전 | 이번 세션 |
|---|---|---|---|---|
| 1 | nosql | DocumentDB + EC2 client app + Secrets Manager + KMS | ap-northeast-2 | 스캐폴드만 |
| 2 | lattice | VPC Lattice로 VPC 간 서비스 통신 (peering/TGW 금지) | ap-northeast-1 | **구현** |
| 3 | event-handling | CloudTrail→EventBridge→Lambda SG 자동복구 + SNS | ap-southeast-1 | 스캐폴드만 |
| 4 | sqs-scaling | SQS + KEDA(min 0/max 6) + Karpenter, 컨트롤러 Fargate | us-west-2 | **구현** |

채점: `asgmt2_moduleN_check.sh` (모듈당 1.25~1.5점 × 5~6항목, 총 30점). 리소스 이름 정확 일치 다수.

## 2. 스캐폴드 + 문서 변환

```
set-08/task-2/
├── task.md, mark.md          # pdfminer.six 추출 → set-08/task-1 형식으로 정리
├── task.pdf, mark.pdf        # 원본 (Git LFS)
├── mark/mark2-1.sh ~ 2-4.sh  # asgmt2_moduleN_check.sh 원본 그대로 복사 (개명만)
├── provided/module-{1..4}/   # 지급파일 4모듈 전부 복사 (원본, 수정 금지)
├── module-1/, module-3/      # 템플릿 그대로 (다음 세션에서 개명·구현)
├── module-2-lattice/
├── module-4-sqs-scaling/
├── NOTES.md, README.md
```

- `_template/task-2` 복사 후 2·4만 개명.
- pdftotext는 한글 소실 → **pdfminer.six**(pip)로 추출. 실패 시 중단하고 보고 (ASCII 재구성 강행 금지).
- 추출본으로 확정해야 할 소실 값: module-4 `pollingInterval`·`PROCESSING_SECONDS`·`consolidationPolicy`, module-2 SG 세부 문구. **구현 전 확정.**

## 3. module-2-lattice (terraform 단일 루트)

### 아키텍처

Client VPC(10.61.0.0/16)의 EC2가 VPC Lattice Service Network를 통해 Service VPC(10.62.0.0/16)의 EC2(:8080)를 호출. VPC peering·TGW 금지(문제지 명시).

```
curl client:80/v1/client/orders?id=1001
  → client_app (SERVICE_URL = Lattice generated domain)
  → Lattice Listener(HTTP/80) → TG(HTTP/8080, INSTANCE)
  → service_app:8080 → {"order_id":"1001","via":"vpc-lattice"}
```

### 파일 구성

| 파일 | 내용 |
|---|---|
| `vpc.tf` | VPC 2개 + 각 public 서브넷·IGW·RT |
| `ec2.tf` | AL2023 × 2. 지급 앱이 stdlib 전용(pip 불필요) → user-data base64 + systemd(Restart=always) — set-07 module-1 검증 패턴 |
| `sg.tf` | client-sg: in 80/0.0.0.0/0(문제지 명시), out은 Lattice managed prefix list(`com.amazonaws.ap-northeast-1.vpc-lattice` data source). service-sg: in 8080 from Lattice prefix list만 — Public IP 직접 접근은 SG로 차단 |
| `lattice.tf` | SN `skills-lattice-sn` / SN-VPC association(client VPC + association SG: in 80 from client CIDR) / Service `skills-lattice-order-service` + SN-service association / TG `skills-lattice-order-tg`(INSTANCE, HTTP/8080, service VPC, health `/health`) + target attachment / Listener `skills-lattice-http-listener`(HTTP/80, default forward) |
| `variables.tf`, `terraform.tfvars` | 이름 전부·CIDR 2개·리전·인스턴스 타입·포트 2개 |
| `outputs.tf` | client public IP, Lattice service domain, SN/TG/Service ID (채점 env 변수와 동일 형태) |

### 핵심 결정

- **SERVICE_URL 주입**: client user-data에 `aws_vpclattice_service.*.dns_entry[0].domain_name`을 terraform 참조로 삽입 — 의존성 순서 자동 해결, 수동 치환 없음. 대가: 도메인 변경 시 client 인스턴스 재생성(user_data 변경).
- **앱 파일 참조**: `provided/module-2/`의 원본을 `filebase64()`로 그대로 임베드. templatefile 미사용(원본 무수정 규칙).
- **둘 다 public 서브넷 + Public IP**: 채점 2-2가 두 인스턴스의 PublicIp 필드를 확인. 차단은 SG 책임.

## 4. module-4-sqs-scaling (terraform + eksctl + helm)

### 아키텍처

SQS 메시지 수에 따라 KEDA가 worker Pod을 0~6개로 스케일, Pod은 Karpenter가 프로비저닝하는 EC2 노드에만 배치. KEDA·Karpenter 컨트롤러는 Fargate.

### 도구 분담 (set-07 module-3 패턴 계승)

| 레이어 | 도구 | 내용 |
|---|---|---|
| 인프라 | terraform | `vpc.tf`(2AZ, public+private 서브넷, NAT 1개), `sqs.tf`(skills-sqs-queue, Standard, visibility 30), `ecr.tf`(worker repo), `iam.tf`(Karpenter controller 정책·노드 role, KEDA operator·worker SA용 SQS 정책 — ARN output) |
| 클러스터 | eksctl `cluster.yaml` | skills-sqs-cluster. terraform output 서브넷 치환. Fargate profile 3개: `skills-sqs-fp-keda`(ns keda)·`skills-sqs-fp-karpenter`(ns karpenter)·**`skills-sqs-fp-kube-system`(ns kube-system, CoreDNS용 — 문제지 외 추가)**. `withOIDC` + IRSA 3개: keda/keda-operator·karpenter/karpenter·skills-sqs/sqs-worker-sa(policy ARN 치환). 노드그룹 없음. public+private endpoint, `authenticationMode: API_AND_CONFIG_MAP` |
| 컨트롤러 | helm (런북) | KEDA 2.x·Karpenter 1.x 최신 안정(repo 규칙: 버전 미고정 예외). SA는 eksctl 사전 생성분 재사용(`create=false`), Karpenter `replicas=1`·`settings.clusterName`. Fargate라 toleration 불필요 |
| 워크로드 | `k8s/` 번호 prefix | `00-namespace`(skills-sqs) → `10-karpenter-nodepool`(NodePool `skills-sqs-nodepool` label `skills-nodepool=event-worker` + EC2NodeClass `skills-sqs-nodeclass`) → `20-deployment`(sqs-worker: sa `sqs-worker-sa`, label/selector `app=sqs-worker`, nodeSelector `karpenter.sh/nodepool=skills-sqs-nodepool`+`skills-nodepool=event-worker`, env `SQS_QUEUE_URL`/`AWS_REGION`/`PROCESSING_SECONDS` 정확 일치) → `30-keda-scaledobject`(ScaledObject `sqs-worker-scaledobject` min 0/max 6/cooldown 30, trigger aws-sqs-queue queueLength 2 + TriggerAuthentication `sqs-worker-trigger-auth` `podIdentity.provider: aws`) |
| 이미지 | CloudShell docker | `app/Dockerfile`(python:3.12-slim + boto3 + 지급 worker.py 무수정). 로컬 Docker 불가 → CloudShell build·push |

### set-07 대비 차이 3개

1. **컨트롤러 Fargate**: CriticalAddonsOnly taint 체계 전부 불필요. 대신 노드그룹이 없어 CoreDNS 자리가 없음 → fp-kube-system 추가 (채점 4-1은 명시 2개 profile 존재만 검사).
2. **min 0 (idle to zero)**: 0→1 활성화는 KEDA operator 직접 폴링 → `pollingInterval` 이번엔 유효 (set-07은 min=1이라 삭제했음 — 결정 로그 참조). 값은 pdfminer 추출로 확정.
3. **TriggerAuthentication 필수** (채점 4-4 직접 조회): set-07의 `identityOwner` 방식 대신 표준 `podIdentity.provider: aws`.

### 스케일 검증 경로 (채점 4-6)

12건 발송 → queueLength 2 → 목표 6 pod(=max) → Karpenter EC2 프로비저닝(~60-90초) → 180초 창 내 워커 노드 배치 확인. cold start(0 pod)부터의 활성화 지연 계산은 NOTES에 기록.

### 치환 가드 (set-07 규칙 계승)

치환 전 변수 비어있음 검사 + 치환 후 placeholder grep 2단계. k8s는 `rendered/` 디렉토리로 전체 렌더링 후 apply.

## 5. 문서·검증

- `README.md`(PS7 런북) + `README.linux.md`(CloudShell 단계 — 번호 stub 규칙 적용, zsh/bash 겸용)
- `NOTES.md`: 모듈 현황 표 4행(1·3은 미착수), 모듈 2·4 채점 커버리지 체크리스트(`[~]` plan 수준), set-07 계승 결정 로그
- `docs/src/content/docs/setlist/set-08/task-2/`: overview·mapping·deployment·runbook (set-07 구성 계승)
- 검증: 모듈 2·4 각각 fmt/validate/plan 클린. helm 값·k8s manifest는 스키마 수준 검토. 채점 항목↔리소스 매핑표 NOTES 기록.

## 6. 지도교사협의회(2026-07-31) 반영

1. **채점지 예상 출력 별도 제공 예정** (8번 과제 명시 언급) → mark.md에 "공식 예상 출력 파일 추후 제공, 도착 시 대조" 추적 항목. 자체 예상 출력은 check 스크립트에서 도출해 임시 기재.
2. **리소스 삭제 금지 정책 가능성** (PowerUser 지급, root 미지급) → destroy·재배포 의존 런북 단계 금지. 이름 충돌 시 삭제 대신 변수 리네임 우회 — 이름 전변수화가 보험. set-07의 "log group 선삭제 후 재apply" 해법은 대회에서 불가할 수 있음 → NOTES 함정 기록.
3. **CloudShell kubectl 필수 요구 확정** (Identity 방식 자유) → public endpoint + API_AND_CONFIG_MAP + access entry fallback 설계 부합. 런북에 CloudShell kubectl 확인 단계 필수 배치.
4. **2과제 당일 최대 +2모듈** (추첨 1인 세트의 4모듈 전체) → 모듈 독립성·전변수화 원칙 재확인. 구조 변경 없음.

## 7. 기각한 대안

- **module-4 전부 terraform**(aws_eks_cluster + helm provider): 도구 일원화 이점 < repo eksctl 관례·검증 자산 폐기·helm provider state 꼬임 리스크.
- **eksctl에 VPC 위임**: VPC 이름·CIDR 변수화(30% 규칙) 불가.
- **CoreDNS용 소형 관리형 노드그룹**: 문제지 무언급 리소스 중 가장 큼. Fargate profile 1개가 최소 침습.
- **task.md ASCII 재구성**: 한글 원문 뉘앙스(채점 세부 기준) 손실 → pdfminer 실패 시에만 재검토.

## 8. 미확정 (구현 전 해소)

- pdfminer 추출로 확정: module-4 `pollingInterval`·`PROCESSING_SECONDS`·`consolidationPolicy` 값, module-2 SG 세부 문구, 채점지 한글 세부 기준.
- terraform plan은 AWS 자격증명 필요 — 없으면 validate까지 하고 plan은 사용자 환경에서.
