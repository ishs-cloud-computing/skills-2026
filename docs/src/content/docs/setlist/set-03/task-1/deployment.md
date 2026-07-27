---
title: 설계 근거
description: 본 PC/bastion/CloudShell 3분할, terraform 2회 apply, 자격증명·환경 선택의 이유
sidebar:
  order: 3
---

실행 절차(명령)는 저장소 런북 `set-03/task-1/README.md`(PowerShell 7) / `README.linux.md`(Linux)에 있다.
이 문서는 그 절차가 **왜 그렇게 짜였는지**만 설명한다.

## 머신 3분할 & 배포 흐름

- ① **본 PC**(PowerShell 7): `terraform apply`(2회) + `eksctl create cluster`.
- ② **bastion**(SSM Session Manager): kubectl/helm 작업·E2E 검증.
- ③ **CloudShell**: 컨테이너 빌드는 **일반 CloudShell**, 제출 전 채점 경로 확인은
  **VPC environment**(`mark-sg`).
- 제공 배포파일(`book`, `index.html`, `main.jpeg`) 원본은 repo 공용 `shared/provided/task-1/`
  (수정 금지)이고, 과제의 `app/` 로 복사해 쓴다. S3 정적 업로드(`s3.tf`)와 App 이미지 빌드가
  모두 `app/` 를 직접 읽으므로 복사가 선행돼야 한다.

## 왜 모든 CLI 를 IAM 사용자(wsc2026-admin)로 실행하나

대회는 root 계정을 지급하지만 유의사항 10(키 정책에 root 금지) 때문에 KMS 5키의 관리자 principal 은
배포자 IAM 신원뿐이다. 따라서 키를 쓰는 모든 작업(terraform·eksctl·docker push·kubectl·채점)이 같은
IAM 신원이어야 한다. root 는 `sts:AssumeRole` 호출이 불가하고, KMS 사용·alias 생성·CMK 테이블/객체
생성도 전부 거부된다(키 정책이 유일한 통제). 그래서 IAM 사용자(`wsc2026-admin`) + 액세스 키를 만들어
이후 전 단계를 이 신원으로 실행한다. root 로 apply 하면 `terraform_data.kms_admin_guard` 가 plan
단계에서 차단한다. 다른 관리자를 추가하려면 `kms_extra_admin_arns` 변수를 쓴다.

## 왜 terraform 을 2회 apply 하나

CloudFront·WAF·버킷 정책·Lambda permission 은 LBC 가 만드는 ALB 에 의존한다. 그래서 1차 apply
(네트워크 + AWS 리소스, CDN 제외) → 클러스터 생성·ingress 로 ALB 확보 → 2차 apply(CDN) 순으로
나눈다. 같은 값을 두 번 쓰므로 `player_number`·`bucket_suffix` 는 `-var` 재입력 대신 tfvars 로 고정한다.

## 왜 fully-private 인데 본 PC 에서 클러스터가 만들어지나

eksctl 은 생성 중 퍼블릭 엔드포인트를 임시로 켰다가 완료 시 닫는다(eksctl 공식 문서 Limitations).
그래서 fully-private 클러스터라도 **생성**은 본 PC 에서 가능하다. 생성이 끝나면 엔드포인트가 private
전용이 되어 이후 K8s API 작업(kubectl·helm·채점)은 VPC 안에서만 된다 — 본 PC 의 kubectl 은 불가.
생성이 중간에 끊기면 퍼블릭 엔드포인트가 열린 채 남을 수 있어 완료 후 상태 확인·재차단이 필요하다.
addon 버전은 지정하지 않는다 — eksctl 이 클러스터 버전의 default 를 설치한다(작업 규칙 2: Addon 미고정).

## 왜 kubectl 작업을 bastion 에서 하나

채점 환경은 VPC CloudShell + `mark-sg` 로 못 박혀 있다(채점 유의 11). 그래서 처음에는 배포도 거기서
했지만, VPC environment 홈은 세션 종료 시 삭제되고(비영속) 업로드 UI 도 없다. manifest 한 줄을
고치려면 본 PC 에서 다시 tar → S3 → 재전개해야 하고, 재접속마다 도구 설치와 `aws configure` 를
반복하게 된다. 배포는 고쳐가며 수렴하는 작업이라 이 왕복 비용이 그대로 시간 손실이 된다.

그래서 작업만 **홈이 유지되는 bastion**(`terraform/bastion.tf`)으로 옮기고, 채점 경로 확인은 제출 전
CloudShell 1회로 분리했다. 설계는 추가 리소스를 최소화하는 쪽으로 잡혀 있다:

- **SG 는 `mark-sg` 를 그대로 붙인다.** `wsc2026-eks-cp-extra-sg` 가 이미 mark-sg → private API 443
  을 허용하므로 새 SG 도, 새 control plane 인그레스도 필요 없다. 부수 효과로 bastion 에서 작업하는
  내내 **채점자가 쓸 경로 그 자체**를 검증하게 된다.
- **app(private) 서브넷 + SSM Session Manager.** SSM·kubectl/helm 다운로드가 NAT 로 해결되어
  Interface Endpoint 를 만들지 않아도 되고(→ Pod Identity 를 깨는 PHZ 문제를 피한다), 접속이
  아웃바운드 기반이라 인바운드 규칙이 0개다. public IP·EIP·SSH 키가 모두 불필요하다.
- **EKS 권한은 인스턴스 역할이 아니라 `aws configure` 로 받는다.** `cluster.yaml` 이
  `bootstrapClusterCreatorAdminPermissions: true` 이므로 클러스터 생성 신원(`wsc2026-admin`)만
  cluster admin 이다. bastion 에서 같은 키를 쓰면 access entry 를 추가하지 않아도 되고,
  인스턴스 역할에는 `AmazonSSMManagedInstanceCore` 만 남는다.

bastion 은 채점 대상이 아니므로 제출 전 `enable_bastion=false` 로 제거한다. 지우기 전에 렌더 결과와
bastion 에서 직접 고친 manifest 를 본 PC 로 회수한다 — 백업을 S3 에 두면 `_transfer/` 정리(mark 6-1)
때 같이 지워지기 때문이다.

한편 신원 자체는 어느 환경이든 `wsc2026-admin` 이어야 한다. 기본 신원(root)으로 돌리면 check_kms
5건·S3 조회·kubectl 이 전부 실패한다. 채점은 심사가 자기들 `mark.sh` 로 수행하며, 저장소의
`mark.sh` 는 우리 재현본이다.

## 왜 이미지 태그가 v1.0.0 단독이고 일반 CloudShell 을 쓰나

mark 3-1 이 이미지 태그 목록 `v1.0.0` 단독 출력을 요구하므로 latest 태그를 만들지 않는다. 빌드는
**일반 CloudShell**(VPC environment 아님)에서 하는데, Docker·업로드 UI 를 지원하고 홈 1GB 가
영속이기 때문이다. CloudShell 은 x86_64 라 `--platform` 도 불필요하다.

## 왜 런북이 PowerShell 7 대상인가 (인코딩)

PS5.1 은 한글이 섞이면 CP949, `>` 리다이렉트는 UTF-16 으로 저장한다. tfvars 에 CP949 가 섞이면
terraform 이 invalid UTF-8 로 실패하고, UTF-16 outputs 는 bastion 의 jq 가 못 읽는다.
PowerShell 7 은 `Set-Content`/`Out-File`/`>` 기본 인코딩이 UTF-8(no BOM)이라 이 문제가 사라진다 —
tfvars 는 terraform 이, outputs.json 은 jq 가 그대로 읽는다. 그래서 런북은 PS7 을 대상으로 하며
`-Encoding` 명시 없이 파일을 생성하고 tfvars 에 한글 주석도 넣을 수 있다.

## 왜 치환을 렌더 파일로 남기나

`eksctl/cluster.yaml` 과 k8s manifest 는 terraform outputs 를 `${VAR}` 자리에 받아야 한다. 치환을
파이프로 흘려보내면(`sed ... | kubectl apply -f -`) 실제로 무엇이 적용됐는지 사후에 확인할 수 없고,
env 가 하나 빠져도 조용히 빈 문자열이 들어간다 — PowerShell 의 `String.Replace(old, null)` 도,
`envsubst` 도 미정의 변수를 예외 없이 지운다. 그래서 치환은 **파일로 남기고 앞뒤로 검사**한다:
치환 전에 manifest 가 요구하는 env 가 전부 등록됐는지 확인하고, 치환 후 잔여 `${}` 가 없는지 본다.
k8s 는 `k8s/rendered/` 미러로 렌더해 `kubectl apply -R -f rendered/` 한 번으로 적용한다.
치환이 필요 없는 manifest 도 같이 복사되므로 apply 지점이 흩어지지 않는다. 다만 PrometheusRule 은
kube-prometheus-stack 이 설치하는 CRD라서, 네임스페이스와 CoreDNS 패치만 helm 앞에서 먼저 적용한다.
