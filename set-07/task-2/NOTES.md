# set-07 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 4개 고정. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 채점 커버 | 미해결 |
|------|------|-----------|--------|
| 1 | module-1-nosql (ap-southeast-1) | 6/6 코드 | 1-4·1-5·1-6 은 실배포 검증 필요 (userdata 완료, 제공 app.py 응답) |
| 2 | module-2-cdn-function (us-east-1) | 6/6 코드 | 2-4·2-5·2-6 은 실배포 검증 필요 (CloudFront 전파 후) |
| 3 | module-3-eks-scaling (ap-northeast-2) | 7/7 코드 | 3-6·3-7 은 실배포 검증 필요. Karpenter IAM Condition 조인 뒤 노드 기동 회귀 미확인 |
| 4 | module-4-container-logging (ap-northeast-1) | 6/6 코드 | **한 번도 apply 하지 않았다** (tfstate 없음). 4-2·4-4·4-5·4-6 전부 미검증, 4-6 은 수동 채점 |

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

- module-1 apply: ~5분 (userdata 완료 대기 포함)
- module-2 apply: ~10분 (CloudFront 배포 포함)
- module-3 apply: ~40분 (`eksctl create` ~20분이 지배적)
- module-4 apply: ~45분 (`eksctl create` ~20분 + helm 4종)
- 공통 병목: `eksctl create cluster`. 모듈 3·4를 가장 먼저 착수한다. 모듈 간 의존성이 없어 병렬 진행 가능.

## 치환 범위 (30% 변동)
<!-- name_prefix / tfvars 만으로 안 끝나는 리터럴. -->

- terraform 리소스 이름·CIDR·리전은 각 모듈 `terraform/terraform.tfvars` 에서 바꾼다.
- `eksctl/cluster.yaml` 의 클러스터명·리전과 `k8s/` 의 클러스터명·리전은 outputs.json 치환 토큰이다. tfvars 만 바꾸면 따라온다.
- 토큰화하지 않은 리터럴 — 바뀌면 손으로 고친다:
  - AZ 접미사 (`module-1/terraform/vpc.tf`, 모듈 3·4 `subnets` 맵, `eksctl/cluster.yaml`)
  - 인스턴스 타입·노드 수 (`eksctl/cluster.yaml`, `k8s/10-karpenter-nodepool.yaml`)
  - 모듈 2 쿠키 이름 `x-sp-ab` — `terraform/policies.tf` 와 `terraform/func/ab-request.js`·`ab-response.js` 3곳
  - 그 외 접두어가 통째로 바뀌면: `grep -rl 'skm-' eksctl k8s | xargs sed -i 's/skm-/<새접두어>-/g'`

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

### 2026-07-25 [module-1,2,3,4] 이름·리전을 tfvars 와 outputs.json 치환 토큰으로 몰았다
- 맥락: 30% 변동으로 접두어·리전이 바뀌면 terraform·eksctl·k8s 세 곳을 손으로 고쳐야 했다. 특히 클러스터명은 eksctl/k8s 에 6번 리터럴로 박혀 있어 하나만 놓쳐도 Karpenter 디스커버리가 조용히 깨졌다.
- 채택: 네트워크 이름은 모듈별 `name_prefix` 변수로, IAM 정책은 이름 대신 terraform output ARN 으로, 클러스터명·리전은 `${CLUSTER_NAME}`·`${REGION}`·`<AWS_REGION>` 치환 토큰으로 바꿨다. 이미 있던 envsubst/Replace 파이프라인을 그대로 쓴다.
- 기각: AZ 접미사·인스턴스 타입·노드 수·쿠키 이름까지 토큰화 → 토큰이 값보다 많아져 런북 가독성이 떨어진다. 대신 각 모듈 README 앞에 이름 대조 단계를 넣고 위 "치환 범위"에 적었다.
- 대가: 토큰이 늘어 런북 치환 단계가 길어졌다. `terraform output -json` 에 `cluster_name` 이 없으면 미치환 토큰으로 `eksctl create` 가 실패한다(module-3 README 의 `${` 가드가 잡는다).
- **미검증**: AWS 자격증명 만료로 `terraform plan` 을 돌리지 못했다. 변수 기본값이 원래 리터럴과 같은지는 코드 대조로만 확인했다. apply 전에 `plan` 이 이름 관련 no-change 인지 반드시 확인한다.

### 2026-07-25 [module-3] Karpenter 인스턴스 프로파일 권한에 클러스터 태그 Condition 추가
- 맥락: 과제지 유의사항 11(최소 권한 원칙). `skm-karpenter-policy` 의 다른 statement 는 전부 클러스터 태그로 스코프돼 있는데 `AllowScopedInstanceProfileActions` 만 `Resource: "*"` 무조건부였다 — 계정 내 임의 인스턴스 프로파일에 임의 역할을 붙일 수 있는 상태.
- 채택: upstream Karpenter 형태로 생성계열은 `aws:RequestTag`, 변경·삭제계열은 `aws:ResourceTag` 의 `kubernetes.io/cluster/<클러스터>=owned` + `topology.kubernetes.io/region` 으로 나눠 건다.
- 기각: 그대로 둔다 → 유의사항 11 위반. `mark3.sh` 가 IAM 을 검사하지 않아 자동 채점에는 안 걸리지만 감점 항목이다.
- 대가: Condition 키가 틀리면 노드 기동이 조용히 실패한다. 적용 후 3-6 스케일아웃으로 회귀 확인이 필요하다.

### 2026-07-24 [module-3,4] bastion 을 없애고 CloudShell 에서 직접 작업
- 맥락: 원래 terraform 이 bastion EC2 를 만들고 거기서 eksctl·helm·docker 를 돌렸다. CloudShell 에 Docker 가 내장돼 있어 bastion 의 유일한 고유 능력이 사라졌다.
- 채택: bastion 리소스를 제거하고 모듈 4는 CloudShell 단독, 모듈 3은 본 PC(클러스터·helm·kubectl) + CloudShell(이미지 빌드)로 나눈다.
- 기각: bastion 유지 → 인스턴스·역할·프로파일 생성/삭제 절차가 과제당 순수 오버헤드고, 채점 전 삭제를 잊으면 정리 감점 위험이 있다.
- 대가: 모듈 3의 `eksctl create`(~20분)를 CloudShell 에서 돌릴 수 없다. CloudShell 은 키보드 유휴 20~30분에 VM 이 회수되며 백그라운드 프로세스·tmux 를 활동으로 치지 않아 장시간 create 가 통보 없이 끊긴다. 그래서 모듈 3만 본 PC 로 남겼다.

### 2026-07-23 [module-4] ALB 를 Terraform 으로 만들고 TargetGroupBinding 으로 연결
- 맥락: 채점 4-2 가 `describe-load-balancers --names o11y-app-alb` 처럼 **이름으로** 조회한다.
- 채택: ALB·TG·리스너를 Terraform 이 이름 지정해 만들고, LBC 는 TargetGroupBinding 으로 Pod IP 만 등록하게 한다.
- 기각: LBC Ingress 로 ALB 생성 → LBC 가 이름을 자동 생성해 지정할 수 없다. 4-2 가 통째로 깨진다.
- 대가: TGB 는 LBC CRD 가 설치된 뒤에만 apply 된다. 런북에 helm 설치 → TGB 순서 제약이 생겼다.

### 2026-07-23 [module-4] AWS Load Balancer Controller 정책을 upstream 원본 그대로 사용
- 맥락: `iam/lbc-policy.json` 에 `Resource: "*"` statement 가 10건 있어 유의사항 11 과 충돌해 보인다.
- 채택: upstream v3.4.2 원본을 그대로 두고 `iam/lbc-policy.version` 으로 버전을 고정한다. 10건 중 2건은 read-only Describe/List 라 `*` 가 불가피하고 4건은 Condition 이 붙어 있다.
- 기각: 조건 없는 write 4건을 직접 축소 → AWS 가 게시한 최소 권한 세트이고, 잘못 좁히면 ALB 생성이 조용히 실패한다. 대회 시간 내 디버깅 비용이 감점보다 크다.
- 대가: 이 파일만 다른 모듈보다 넓은 권한을 갖는다. 버전을 올릴 때 정책 diff 를 다시 봐야 한다.

### 2026-07-23 [module-4] OTel Collector 를 helm 이 아니라 raw manifest 로 배포
- 맥락: 채점 4-3 이 DaemonSet 이름 `o11y-otel` 을 정확히 본다.
- 채택: RBAC·ConfigMap·DaemonSet 3파일을 직접 쓴다. 이름과 파이프라인 설정이 코드에 그대로 보인다.
- 기각: opentelemetry helm chart → 이름 규칙과 기본 파이프라인을 차트 버전이 좌우한다. 4-5 의 `k8s_namespace_name` 라벨 승격까지 values 로 우겨넣어야 한다.
- 대가: 차트가 해주는 업그레이드·기본값 추종을 잃는다. 이 과제 한정이라 무관하다.

### 2026-07-23 [module-3,4] 클러스터 엔드포인트를 public + private 둘 다 켠다
- 맥락: 채점 스크립트가 CloudShell 에서 `update-kubeconfig` 후 kubectl 로 붙는다.
- 채택: `publicAccess: true` + `privateAccess: true`. 노드 조인 통신은 VPC 내부로 유지된다.
- 기각: private-only (set-05 방식) → 채점 셸이 VPC 밖이라 API 서버에 닿지 못한다.
- 대가: API 엔드포인트가 인터넷에 노출된다. 접근 제어는 EKS 인증에만 의존한다.

### 2026-07-23 [module-4] 제공 Dockerfile 대신 자체 Dockerfile 로 빌드
- 맥락: 제공 `Module4-Container-Logging/Dockerfile` 이 flask 를 설치하지 않고 `requirements.txt` 도 없다. 그대로 빌드하면 Pod 가 CrashLoop 된다.
- 채택: `module-4-container-logging/app/Dockerfile` 을 따로 두고 제공 `app.py` 만 복사해 빌드한다.
- 기각: 제공 Dockerfile 수정 → `provided/` 는 수정 금지.
- 대가: 대회 당일 제공본이 고쳐져 나오면 제공본을 우선 써야 한다. 빌드 전에 제공 Dockerfile 을 한 번 확인한다.

### 2026-07-22 [module-2] KVS 키를 `keys_exclusive` 로 선언
- 맥락: 채점 2-6 이 weight 를 1.0/0.0 으로 바꿨다가 0.3 으로 되돌린다.
- 채택: `aws_cloudfront_key_value_store` + `keys_exclusive` 로 선언값이 곧 전체 키 집합이 되게 한다. 채점이 남긴 drift 는 재-apply 로 수렴한다.
- 기각: 키를 개별 리소스로 관리 → 채점이 값을 바꾼 뒤 상태가 어긋나면 어느 키가 틀렸는지 추적하기 어렵다.
- 대가: KVS 에 수동으로 넣은 키는 apply 때 지워진다.

---
## 함정 / 알려진 한계
<!-- 덮어쓴다. 결정 로그와 달리 현재 상태를 유지한다. -->

### 모듈 1
- 1-5/1-6 은 매번 새 `train_id` 로 실행되어 재시도에 안전하다. 감사 테이블 적재는 Stream → Lambda 경유로 수 초 걸린다(채점이 `sleep 30` 을 포함).
- EC2 8080 인바운드가 `0.0.0.0/0` 이다. 채점 1-4 가 퍼블릭 curl 로 `/healthcheck` 를 때려 좁힐 수 없다.
- Lambda zip 의 엔트리 파일 이름이 제공 `lambda.py` 그대로라 handler 가 `lambda.handler` 다. 제공 파일명이 바뀌면 `lambda.tf` 의 handler 도 같이 바꾼다.

### 모듈 2
- apply 완료 후에도 함수·KVS 변경 전파에 수십 초 걸린다. 2-6 채점 스크립트가 60회 재시도를 포함하지만, 수동 확인은 바로 하지 않는다.
- 버킷 정책 Statement 는 **1개만** 둔다 — 채점 2-1 이 `Statement[0]` 만 본다.
- `x-sp-ab-assigned` 요청 헤더는 **신규 배정 시에만** 설정한다. 쿠키가 이미 있는 요청에도 설정하면 응답 함수가 Set-Cookie 를 붙여 2-4 의 no_setcookie 검사가 깨진다.

### 모듈 3
- **addon 노드 1대 용량**: t3.medium 1대에 coredns 2 + KEDA 3 + Karpenter 1 이 올라간다. Karpenter requests 를 0.5 vCPU/512Mi 로 낮춰 설치한다(런북 반영). 그래도 Pending 이면 KEDA metricServer/webhooks requests 를 추가로 낮춘다.
- **KEDA 차트 tolerations 스키마**(작업규칙 7): addon 노드가 taint 되어 있어 KEDA Pod 에 toleration 이 필요하다. 차트 2.20.1 은 최상위 `tolerations` 값을 쓰지만 버전이 바뀌면 `helm show values kedacore/keda --version <버전> | grep -n -A3 tolerations` 로 키를 재확인한다. Pending Pod 가 남으면 이것부터 의심한다.
- **스케일인 창 2.5분**: ScaledObject `stabilizationWindowSeconds: 30` 과 NodePool `consolidateAfter: 60s` 가 한 쌍이다. 어느 쪽도 늘리지 않는다. 채점 3-7 의 대기가 최대 2.5분이다.
- Deployment 의 `env` 는 리터럴 3개만 유지한다. 채점 3-3 이 `name=value` 로 정확 비교하므로 `valueFrom` 이나 추가 env 를 넣으면 깨진다.

### 모듈 4
- **OTel 재시작 시 로그 유실**: filelog 가 `start_at: end` 이고 체크포인트 저장소를 두지 않았다. 채점은 채점 시점에 새로 생성되는 로그만 보므로 문제 없지만, 콜렉터 재시작 직전 로그는 유실된다. 필요해지면 file_storage extension 으로 체크포인트를 추가한다.
- **Grafana 패널 데이터**: No Data 패널이 하나라도 있으면 4-6 오답. 채점 전 `/log?level=info|warn|error` 를 각각 호출해 3개 레벨 데이터를 만들어 둔다.
- 채점 4-5 의 LogQL 라벨은 `k8s_namespace_name`(OTLP 리소스 속성 승격), level 값은 대문자 `ERROR` 다. OTel 이 본문을 가공하면 `| json` 파싱이 깨지므로 filelog 의 `container` 파서 외 본문 변형을 추가하지 않는다.
- Grafana 범례가 `{level="ERROR"}` 형태로 보이면 4-6 오답이다. 대시보드 쿼리는 `sum by (level)` + `legendFormat {{level}}` 을 유지한다.

### 공통
- **mark1/2/4 는 `rm -rf ~/.aws` 를 수행한다**. CloudShell 에서만 실행한다. CloudShell 자격증명은 콘솔 세션 기반이라 삭제와 무관하다. mark3 은 이 삭제를 하지 않아 클러스터 접근이 유지된다.
- task-2 는 공통 root 신원이다. 클러스터 생성자 신원이 곧 채점 셸의 kubectl 권한이므로 `aws configure` 로 별도 IAM 키를 넣지 않는다. 다른 신원으로 만들었다면 `aws eks create-access-entry` + `associate-access-policy` 로 채점 셸 ARN 에 `AmazonEKSClusterAdminPolicy` 를 부여한다.
