---
title: 설계 근거
description: 본 PC/CloudShell 2분할, terraform 2회 apply, 자격증명·환경 선택의 이유
sidebar:
  order: 3
---

실행 절차(명령)는 저장소 런북 `set-03/task-1/README.md`(PowerShell 7) / `README.linux.md`(Linux)에 있다.
이 문서는 그 절차가 **왜 그렇게 짜였는지**만 설명한다.

## 머신 2분할 & 배포 흐름

- ① **본 PC**(PowerShell 7): `terraform apply`(2회) + `eksctl create cluster`.
- ② **CloudShell**: 컨테이너 빌드는 **일반 CloudShell**, kubectl/helm 작업·E2E·채점은
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

## 왜 VPC CloudShell 이 채점 환경인가

kubectl/helm/채점은 VPC environment(`mark-sg` — 채점 유의 10·11 과 동일 SG)에서 한다. 이 환경이
그대로 채점 환경이므로(채점 유의 11), 작업 내내 채점 경로(mark-sg → EKS API, wsc2026-admin 신원)를
상시 검증하는 셈이다. 기본 신원(root)으로 돌리면 check_kms 5건·S3 조회·kubectl 이 전부 실패한다.
단, VPC environment 홈은 세션 종료 시 삭제되고(비영속) 업로드 UI 도 없다 — 그래서 도구·파일·kubeconfig
는 셋업 블록 하나로 복구하고, 본 PC↔CloudShell 파일 전달은 S3 릴레이(`_transfer/`)를 쓴다.

채점은 심사가 이 환경에서 자기들 `mark.sh` 로 수행한다. 저장소의 `mark.sh` 는 우리 재현본이라 런북·S3
릴레이에서 제외했다 — 자가확인이 필요하면 레포 원본을 수동으로 붙여넣어(`vi ~/wsc2026/mark.sh`) 돌린다.

## 왜 이미지 태그가 v1.0.0 단독이고 일반 CloudShell 을 쓰나

mark 3-1 이 이미지 태그 목록 `v1.0.0` 단독 출력을 요구하므로 latest 태그를 만들지 않는다. 빌드는
**일반 CloudShell**(VPC environment 아님)에서 하는데, Docker·업로드 UI 를 지원하고 홈 1GB 가
영속이기 때문이다. CloudShell 은 x86_64 라 `--platform` 도 불필요하다.

## 왜 런북이 PowerShell 7 대상인가 (인코딩)

PS5.1 은 한글이 섞이면 CP949, `>` 리다이렉트는 UTF-16 으로 저장한다. tfvars 에 CP949 가 섞이면
terraform 이 invalid UTF-8 로 실패하고, UTF-16 outputs 는 CloudShell 의 jq 가 못 읽는다.
PowerShell 7 은 `Set-Content`/`Out-File`/`>` 기본 인코딩이 UTF-8(no BOM)이라 이 문제가 사라진다 —
tfvars 는 terraform 이, outputs.json 은 jq 가 그대로 읽는다. 그래서 런북은 PS7 을 대상으로 하며
`-Encoding` 명시 없이 파일을 생성하고 tfvars 에 한글 주석도 넣을 수 있다.
