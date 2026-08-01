---
title: 설계 근거
description: 8세트 2과제 — 왜 이렇게 구성했는가 (explanation)
sidebar:
  order: 3
---

각 선택의 "왜"만 다룬다. 실행 절차는 [런북](../runbook/), 채점 대조는 [매핑](../mapping/) 참고.

## 모듈 1 — 왜 인덱스를 별도 스크립트로 만드는가

지급 `docdb_client.py`는 인덱스를 나열(`/v1/admin/indexes`)할 뿐 생성하지 않는다. 그런데 채점 1-4는 과제지 3-3의 인덱스 8종(TTL 포함)이 실제로 존재해야 통과한다. 지급 앱은 수정 금지이므로 생성 코드는 앱 밖에 있어야 하고, DocumentDB는 외부 비노출이라 로컬·CloudShell에서 접속할 수도 없다. 남는 자리는 클러스터와 같은 VPC에 있는 Client EC2뿐이다 — terraform이 `index_setup.py`를 렌더링해 user-data로 배치하고, seed 직후 실행한다. `create_index`는 멱등이라 부팅 재시도 루프에 안전하게 들어간다.

## 모듈 1 — 왜 user-data가 gzip 임베드인가

module-2는 지급 앱을 평문 base64로 user-data에 임베드했다. 같은 방식이면 module-1은 앱(9KB)+데이터셋(5KB)의 base64 팽창(×1.37)만으로 EC2 user-data 한도(16KB)를 넘는다. terraform `base64gzip()`으로 압축 임베드하면 총 ~7KB로 수렴하고, S3 스테이징 버킷(추가 리소스·IAM·업로드 순서)을 만들 필요가 없어진다.

## 모듈 3 — 왜 EventBridge 패턴에 groupId 필터가 없는가

rule 패턴을 보호 SG의 `groupId`까지 좁히면 Lambda 호출 자체를 줄일 수 있다. 그러나 CloudTrail 이벤트에서 groupId가 놓이는 위치는 요청 형태(단건 파라미터/중첩 목록)에 따라 달라 필터가 이벤트를 놓칠 수 있고, 지급 Lambda가 이미 보호 SG가 아닌 이벤트를 IGNORED로 걸러낸다. 감지 누락(채점 실패)과 불필요한 호출(무해) 중 후자를 받아들이는 선택이다.

## 모듈 3 — 왜 EC2에 IGW조차 없는가

채점 3-1은 EC2가 running이고 보호 SG가 연결돼 있는지만 본다. 이 EC2는 트래픽을 받지도 보내지도 않는 "보호 대상 표본"이라 IGW·Public IP·NAT 어느 것도 필요 없다. 미사용 리소스를 줄이면 30% 변동 때 재작성 표면도 줄어든다.

## 모듈 4 — 도구 3분담: terraform / eksctl / helm

이 모듈은 클러스터 밖 리소스, 클러스터 자체, 컨트롤러 배포물, 이렇게 성격이 다른 세 층을 갖는다. 경계를 도구별로 고정한다:

- **terraform** — VPC·SQS·ECR·IAM(정책·IRSA 롤) 등 클러스터와 무관하게 존재하는 AWS 리소스. 이름 정확 일치 채점 항목이 많아 변수화가 필요하고(30% 변동 대비), 클러스터 생성(~15-20분)과 수명주기가 달라 독립적으로 빠르게 재적용할 수 있어야 한다.
- **eksctl (`cluster.yaml`)** — 생성 시점에 굳는 것 전부: 클러스터 리전·버전, Fargate Profile 3개, OIDC/IRSA ServiceAccount 3개, access entry, 엔드포인트, addon(coredns 등). 생성 후 변경이 곤란한 축(OIDC, 엔드포인트, addon computeType)을 한 파일에 선언해 재현성을 확보한다. `aws_eks_cluster` terraform 리소스로도 가능하지만 Fargate Profile·IRSA·access entry 보일러플레이트가 커서, eksctl은 이들을 선언 한 번으로 묶어 대회 시간 제약에서 이득이 크다.
- **helm** — 컨트롤러(KEDA·Karpenter)만. 자체 CRD·RBAC를 가진 배포물은 매니페스트 직접 관리보다 helm chart가 저렴하다.
- **kubectl** — 워크로드·CRD 인스턴스 매니페스트(NodePool, ScaledObject, Deployment). 번호 prefix(`00-`, `10-`, …)로 apply 순서를 강제한다.

## 모듈 4 — 왜 컨트롤러를 Fargate에 두는가

과제지 6-2는 Fargate Profile을 `keda`·`karpenter` 네임스페이스에 대해 명시적으로 요구한다 — 즉 컨트롤러 자체는 서버리스로 띄우라는 뜻이다. 반면 워커(6-5)는 "Fargate가 아닌 Karpenter EC2 Worker Node"에서 실행되어야 한다는 정반대 제약을 받는다. 두 제약을 동시에 만족하려면 클러스터에 Managed NodeGroup 없이 시작해야 하는데, 그러면 CoreDNS가 앉을 노드가 구조적으로 없다.

여기서 나오는 선택이 coredns EKS addon을 `configurationValues: {"computeType": "Fargate"}`로 강제하고, 이를 받을 `skills-sqs-fp-kube-system` Fargate Profile을 과제지 명시분(2개) 외에 추가하는 것이다. 대안으로 소형 Managed NodeGroup을 하나 두어 CoreDNS를 거기 앉히는 방법도 있었지만, 과제지가 요구하지 않는 최대 크기의 상시 리소스를 추가하는 셈이라 기각했다 — 채점 4-1은 명시된 2개 Profile의 존재만 검사하므로 추가 Profile 자체는 감점 요인이 아니다.

Fargate 위 Karpenter 컨트롤러가 자신이 의존하는 CoreDNS의 기동을 기다리는 순환 의존을 피하기 위해, Karpenter helm 값에 `dnsPolicy=Default`를 추가해 VPC 리졸버로 직행하게 했다 — 컨트롤러는 쿠버네티스 서비스 이름을 조회할 필요가 없어 이 완화의 부작용이 없다.

## 모듈 4 — 왜 min 0 KEDA 설정을 그대로 살렸는가

과제지 6-6은 `min 0, max 6, pollingInterval 15초 이하`를 명시한다. `minReplicaCount: 0`인 ScaledObject는 0→1 활성화 감지를 HPA가 아니라 KEDA operator의 직접 폴링(`pollingInterval`)에 의존한다 — 이는 이전 세트(set-07 module-3)에서 "min=1이면 pollingInterval이 완전히 무효"라는 이유로 필드를 삭제했던 것과 전제 자체가 다르다. min이 0인 이번 설계에서는 `pollingInterval: 15`가 실제로 스케일 감지 지연에 영향을 주는 유효한 값이라 그대로 둔다.

## 모듈 2 — 왜 SN-VPC association을 Client VPC에만 두는가

과제지 4-4는 Service Network의 VPC Association을 Client VPC에 대해서만 명시한다. Target Group이 `config.vpc_identifier`로 Service VPC를 직접 참조하므로, Lattice는 이 필드만으로 target(Service EC2)에 도달하고 헬스체크를 수행할 수 있다. Service VPC까지 SN에 추가로 연결하는 것은 과제지 미요구 리소스를 늘릴 뿐 트래픽 경로에 필요하지 않다.

## 모듈 2 — 왜 Service 보안그룹이 Prefix List 전용인가

과제지 4-3은 "TCP/8080은 VPC Lattice Managed Prefix List 소스만 허용, 0.0.0.0/0 허용 시 미충족"을 조건문 형태로 명시한다. Service EC2는 Public IP도 없고 Client VPC와 직접 연결도 없으므로, 유일한 정당한 진입 경로는 Lattice 데이터 플레인이다. Managed Prefix List(`com.amazonaws.<region>.vpc-lattice`)를 소스로 지정하면 이 경로만 열리고, 실수로 CIDR 블록을 추가하는 순간 채점 조건을 정면으로 어기게 된다는 것을 SG 자체가 구조적으로 방지한다.
