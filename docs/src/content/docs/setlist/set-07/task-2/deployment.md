---
title: 설계 근거
description: 7세트 2과제 — 왜 이렇게 구성했는가 (explanation)
sidebar:
  order: 3
---

각 선택의 "왜"만 다룬다. 실행 절차는 [런북](../runbook/), 채점 대조는 [매핑](../mapping/) 참고.

## 모듈 1 — NoSQL

### 왜 자체 VPC인가

과제지 자체는 VPC를 요구하지 않아 default VPC가 최소 구성이지만, 대회 당일 30% 변동으로 "VPC 이름/CIDR 지정"이 추가될 수 있다. data source 기반 default VPC는 변수화할 이름·CIDR이 코드에 없어서 그 변동을 흡수하지 못한다 — retrofit 시 리소스 5개 신규 작성에 서브넷 교체로 인스턴스까지 재생성된다. 자체 VPC(+public 서브넷·IGW·라우팅, 전부 무료)는 리소스 5개를 미리 지불하고 이름·CIDR을 `vpc_name`/`vpc_cidr`/`subnet_cidr` 변수로 열어둔다. default VPC가 삭제된 계정에서도 동작한다는 부수 이득도 있다.

### 왜 GSI를 key_schema 블록으로 선언하나

AWS provider 6.x에서 `global_secondary_index`의 `hash_key`/`range_key` 인자는 deprecated다(6.56 문서 기준). `key_schema` 블록이 현행 문법이며, 결과 리소스는 동일하다.

### 왜 GSI 키가 user_id/reserved_at인가 (sparse의 핵심)

채점 1-6-A는 취소 후 `/my-bookings` 조회가 0건이 되는지 본다. DynamoDB GSI는 키 속성이 없는 아이템을 인덱스에 넣지 않는다(sparse). 지급 `app.py`가 취소 시 `REMOVE user_id, reserved_at`을 수행하므로, GSI 키를 정확히 이 두 속성으로 잡아야 취소된 예약이 인덱스에서 자동 제외된다. 인프라 쪽에 sparse "설정"은 없다 — 키 선택이 곧 설정이다.

### 왜 handler가 lambda.handler인가

지급 파일 `lambda.py`는 무수정 사용 조건이다. 파일명이 python 예약어 `lambda`와 같지만, Lambda 런타임은 모듈을 importlib로 로드하므로 `import lambda` 구문 제약과 무관하게 동작한다. zip 내부 파일명을 개명하는 우회(archive_file `source` 블록)는 불필요해서 기각했다.

### 왜 app.py를 user-data로 배포하나

module-1은 Dockerfile이 지급되지 않았다 — EC2 직접 실행이 전제다. app.py + requirements.txt는 base64로 ~7KB라 user-data 16KB 한도 안에 넉넉히 들어간다. S3 경유는 버킷·IAM·순서 의존만 늘린다. systemd `Restart=always`로 pip 설치가 끝나기 전 기동 실패를 자동 복구한다.

### 왜 ESM이 정확히 1개여야 하나

채점 1-3-A는 `list-event-source-mappings` 출력 전체를 기대값과 정확 일치로 비교한다. 트리거가 2개면 출력 줄이 늘어 실패한다. 같은 이유로 GSI도 1개만 둔다(1-2-A).

### IAM 범위

유의사항 11이 `Principal:"*"`·`Action:"*"`을 금지한다. EC2 롤은 앱이 실제 호출하는 `UpdateItem`(예약/취소)과 `Query`(테이블+GSI)만, Lambda 롤은 스트림 읽기 3종 + audit `PutItem` + 로그 쓰기만 갖는다.

## 모듈 2 — CDN Function

### 왜 CloudFront Functions + KeyValueStore인가

핵심 요구는 "노출 비율 변경이 코드 재배포 없이 즉시 반영"이다. 비율을 함수 코드에 상수로 넣으면 변경 = 재배포라 요구를 정면으로 어긴다. KVS는 함수 코드와 분리된 엣지 설정 저장소로, `put-key` 한 번이면 발행 없이 전 엣지에 전파된다 — 채점 2-6이 정확히 이 동작(weight 1.0/0.0 변경 → test-function 즉시 반영)을 검사한다. Lambda@Edge는 KVS를 못 쓰고(CF Functions 전용) 배포 전파도 분 단위라 기각. KVS를 쓰려면 런타임이 `cloudfront-js-2.0`이어야 하는데, 이는 과제지 요구이기도 하다.

### 왜 Set-Cookie를 viewer-response에서 assigned 헤더로 게이트하나

배정 유지(sticky)의 정합성은 "첫 방문에만 쿠키 발급"에 달려 있다. viewer-request 함수는 신규 배정일 때만 요청 헤더 `x-sp-ab-assigned`를 세우고, viewer-response 함수는 이 헤더가 있을 때만 `Set-Cookie`를 붙인다. 이렇게 하면 재방문(쿠키 보유) 응답에는 Set-Cookie가 절대 없다 — 채점 2-4가 이를 정확 검사한다. viewer-response는 캐시 **뒤**에서 실행되므로 Set-Cookie가 캐시에 저장돼 다른 방문자에게 새는 일도 구조적으로 없다. 대안인 "response에서 request.cookies 부재로 판단"은 배정된 버전(a/b)을 알 방법이 없어 URI 재파싱이 필요해 기각. Set-Cookie 자체는 `response.headers`가 아니라 `response.cookies` 객체로만 설정된다(CloudFront Functions 이벤트 구조).

### 왜 캐시 키에 x-sp-ab 쿠키인가

버전 분리는 사실 viewer-request의 URI 재작성(캐시 조회 전에 실행)만으로도 일어난다 — 캐시 키에 URI가 포함되기 때문이다. 그럼에도 쿠키를 whitelist로 캐시 키에 넣는 것은 과제지 명시 요구이자 채점 2-3 검사 항목이고, URI 재작성 로직이 바뀌어도 A/B 캐시가 섞이지 않게 하는 방어선이다. AWS Managed Policy 금지 조건 때문에 TTL 0/300/3600의 커스텀 캐시 정책과 커스텀 Security Header 정책을 만든다.

### 왜 KVS 키를 keys_exclusive 단일 리소스로 관리하나

채점 2-2는 `list-keys` 출력을 기대값과 정확 일치로 비교한다 — 키가 3개를 초과하면 실점. `aws_cloudfrontkeyvaluestore_keys_exclusive`는 선언 안 된 키를 제거해 "정확히 3개"를 구조적으로 보장하고, 키별 개별 리소스 대비 KVS API 호출도 적다. 대가는 이 리소스가 키 전체의 단독 소유자가 된다는 것인데, 채점 2-6의 out-of-band weight 변경은 스크립트가 스스로 0.3으로 복원하므로 충돌하지 않는다.

### 왜 "Pay-as-you-go 타입"인데 아무 설정이 없나

CloudFront의 flat-rate 요금 플랜(2025-11 출시)은 콘솔 전용 opt-in 구독이고, Terraform·API·CloudFormation에는 플랜 인자 자체가 없다. 즉 Terraform으로 만든 distribution은 구조적으로 pay-as-you-go다. `price_class`는 엣지 로케이션 범위 설정으로 과금 모델과 무관하므로 건드리지 않는다. 부수적으로, 플랜 구독 distribution은 삭제 불가·함수/KVS 공유 불가 제약이 있어 채점용 임시 스택과도 상성이 나쁘다.

### 왜 S3 접근이 OAC인가

과제지가 "CloudFront만 접근 + OAC"를 명시한다. 버킷은 Public Access 전면 차단이고, 버킷 정책은 `cloudfront.amazonaws.com` service principal에 `AWS:SourceArn`을 이 distribution ARN으로 조건 건 단일 statement다 — 채점 2-1이 `Statement[0]` 하나만 검사하므로 statement를 늘리지 않는다. 레거시 OAI는 deprecated라 기각.

## 모듈 3·4 공통 — EKS 도구 분담

### 왜 terraform / eksctl / helm / kubectl 네 층인가

이 과제에는 EKS 클러스터가 두 개다 — 모듈 3 `skm-eks-cluster`(ap-northeast-2), 모듈 4 `o11y-cluster`(ap-northeast-1). 두 클러스터 모두 같은 경계 기준으로 도구를 나눈다: **AWS API로 만들어지는 클러스터 밖 리소스는 terraform, 클러스터 자체는 eksctl, 차트 배포물은 helm, 클러스터 안 오브젝트는 kubectl.**

- **terraform** — VPC·SQS·ECR·IAM 정책/롤 등 클러스터 밖 리소스. 이름 정확 일치 채점 항목이라 변수화가 필요하고(30% 변동 대비), 클러스터 생성(~15분)과 수명주기가 달라 독립적으로 빠르게 재적용할 수 있어야 한다.
- **eksctl (`cluster.yaml`)** — 생성 시점에 굳는 것 전부: 클러스터 버전, Managed NodeGroup(이름·taint·`instanceName`), addons, OIDC/IRSA ServiceAccount, access entry, 엔드포인트. 생성 후 변경이 불가하거나(OIDC·엔드포인트) 곤란한 축이라 한 파일에 선언한다. terraform `aws_eks_cluster`로도 가능하지만 MNG·IRSA·access entry 보일러플레이트가 크고, eksctl은 이들을 선언 한 번으로 묶는다 — 대회 시간 제약에서 결정적.
- **helm** — 컨트롤러(모듈 3의 KEDA·Karpenter)만. 자체 CRD·RBAC를 가진 배포물은 매니페스트 직접 관리가 더 비싸다. 컨트롤러가 없는 모듈 4는 이 층을 생략할 수 있다.
- **kubectl** — 워크로드·CRD 인스턴스 매니페스트. 번호 prefix(`00-`, `10-`, …)로 apply 순서를 강제한다.

### 왜 두 클러스터를 완전히 분리하나

리전이 다르고(ap-northeast-2 / ap-northeast-1) 공유 리소스가 없다. 모듈 디렉토리별로 terraform 스택·`cluster.yaml`을 독립시키면 한 모듈의 변경·재생성이 다른 모듈에 번지지 않고, 클러스터 생성(각 ~15분)을 병렬로 돌릴 수 있다.

kubeconfig도 같은 원칙으로 나눈다: 공유 `~/.kube/config`에 컨텍스트 두 개를 두고 `use-context`로 전환하는 방식은 전환을 잊는 휴먼 에러가 남고, kubectl뿐 아니라 helm까지 조용히 잘못된 클러스터로 간다. 대신 모듈 디렉토리마다 자기 kubeconfig 파일을 두고(gitignored) 모듈 전용 터미널에서 `KUBECONFIG` 환경변수로 고정한다 — **터미널 1개 = 클러스터 1개**라 다른 클러스터를 칠 방법 자체가 없고, 재부팅(파일 초기화) 후에도 `aws eks update-kubeconfig --kubeconfig <경로>` 한 줄로 복구된다. eksctl은 클러스터 생성 시 `KUBECONFIG` 경로에 kubeconfig를 써 주므로 추가 절차가 없다.

## 모듈 3 — EKS Scaling

### 왜 addon NG taint가 CriticalAddonsOnly인가

과제지는 "taint로 Addon NG에서 App이 실행되지 않도록"만 요구하므로 키는 자유지만, 그 NG에서 돌아야 하는 시스템 컴포넌트들이 taint를 톨러레이트해야 한다. `CriticalAddonsOnly=true:NoSchedule`은 CoreDNS EKS addon의 기본 toleration과 Karpenter helm chart의 기본 toleration에 이미 포함돼 있어 두 컴포넌트가 무설정으로 스케줄된다. KEDA chart만 기본 tolerations가 비어 있어 helm 값 하나를 추가한다. 커스텀 키를 쓰면 세 컴포넌트 모두에 toleration을 주입해야 해서 관리 지점만 늘어난다. 앱 Pod는 이 toleration이 없으므로 addon NG에 진입할 수 없다.

### 왜 노드 Name 태그가 instanceName인가

채점 3-2는 EC2 인스턴스의 `tag:Name`을 검사한다. EKS Managed NodeGroup의 `tags`는 NG 리소스 자체에만 붙고 인스턴스에 전파되지 않으므로, eksctl이 launch template TagSpecifications로 인스턴스 Name 태그를 만들어 주는 `instanceName` 필드가 유일한 충족 경로다. set-05의 `tags: {Name: ...}` 패턴은 해당 항목이 미채점이라 드러나지 않았을 뿐 여기서는 실패한다.

### 왜 앱이 nodeSelector + NodePool taint 양방향인가

과제지 요구가 대칭 두 개다: 앱은 `skm-app-nodepool`에서만(→ Deployment에 `karpenter.sh/nodepool` nodeSelector), 그 노드에는 앱·DaemonSet 외 실행 금지(→ NodePool template에 `dedicated=app:NoSchedule` taint + 앱만 toleration 보유). taint는 채점 3-5의 `taints | length ≥ 1` 검사 항목이기도 하다. 채점 3-3이 1 replica 상시 상태에서도 앱 Pod의 노드에 nodepool 라벨이 있는지 보므로, nodeSelector 없이는 addon NG에 앉은 Pod가 실점을 만든다.

### 왜 퍼블릭 엔드포인트인가 (set-05와 반대)

mark3.sh는 일반 CloudShell에서 kubectl을 실행한다. CloudShell은 VPC 밖이므로 private 엔드포인트로는 접근 자체가 안 된다. set-05의 private+bastion 구조는 그 세트의 요구였을 뿐이다. 엔드포인트만 public으로 열고 노드는 private 서브넷 + NAT에 둔다. `API_AND_CONFIG_MAP` 인증 모드로 채점 주체가 클러스터 생성자와 달라도 access entry를 추가할 수 있게 한다.

### 왜 scale-in에 HPA behavior 오버라이드가 필요한가

채점 3-7은 purge 후 150초 안에 Pod 1·노드 1을 요구한다. HPA의 scale-down 안정화 기본값이 300초라 기본 설정으로는 구조적으로 통과가 불가능하다. ScaledObject의 `advanced.horizontalPodAutoscalerConfig`로 안정화를 15초로 줄이면: purge → HPA sync(~15초)로 감지 → ~35초에 Pod 1 → 빈 노드 60초(consolidateAfter, 과제지 고정값) → ~140초에 노드 반환. `pollingInterval`은 쓰지 않는다 — minReplicaCount가 1 이상이면 스케일링은 전부 HPA 폴링으로 일어나 이 필드가 무효이기 때문이다(KEDA webhook이 경고한다). Karpenter 쪽을 줄이는 선택지는 과제지가 60초를 명시해 없다.

### 왜 스케일 아웃이 노드 2대를 보장하나

t3.medium(2 vCPU)의 allocatable은 약 1930m, DaemonSet(aws-node·kube-proxy)을 빼면 약 1805m — 500m 요청 Pod는 노드당 최대 3개다. KEDA가 메시지 100건에 max 5 replica로 올리면 나머지 2개는 Pending이 되고, Karpenter가 이를 감지해 두 번째 노드를 프로비저닝한다. 즉 채점 3-6의 "노드 ≥2"는 리소스 requests 값에 의해 구조적으로 보장된다.

### IAM 범위

유의사항 11에 따라 세 주체를 분리한다: KEDA는 큐 길이 조회(`GetQueueAttributes`·`GetQueueUrl`), 앱은 소비(`ReceiveMessage`·`DeleteMessage`·`GetQueueAttributes`) — 모두 해당 큐 ARN 한정. Karpenter 컨트롤러는 공식 정책 기반으로 인스턴스 생성·삭제를 클러스터/nodepool 태그 조건으로 스코프한다. 셋 다 IRSA로 바인딩해 노드 롤에는 아무 SQS 권한도 두지 않는다.
