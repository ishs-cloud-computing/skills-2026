---
title: 런북 설계 노트
description: 8세트 2과제 배포 런북의 설계 이유 (explanation)
sidebar:
  order: 2
---

실제 배포·채점 명령은 각 모듈 README(`module-2-lattice/README.md`, `module-4-sqs-scaling/README.md`)가 소유한다. 이 페이지는 그 런북이 왜 이런 모양인지만 다룬다.

## 왜 치환 가드가 2단계인가

module-4의 `cluster.yaml`·`k8s/*.yaml`은 `${ACCOUNT_ID}`·`${VPC_ID}`·`${ECR_IMAGE}` 같은 플레이스홀더를 terraform output 값으로 치환한 뒤 apply한다. set-07에서 이미 겪은 문제가 그대로 재현될 수 있다는 게 출발점이다: PowerShell 7의 `.Replace()`는 대상 변수가 비어 있어도 예외 없이 빈 문자열을 그대로 끼워 넣는다. 치환 후 `grep '\${'`(또는 `Select-String`)만으로는 "플레이스홀더가 남아 있는가"는 잡아도 "값이 비어서 조용히 사라졌는가"는 잡지 못한다 — 두 실패 모드가 다르다.

그래서 가드를 두 단계로 나눈다.

1. **치환 전**: `if (!$env:ACCOUNT_ID -or !$env:VPC_ID -or ...) { throw }`로 원본 변수가 비어 있는지 먼저 확인한다. 이 단계가 없으면 사이 단계의 실패(예: terraform output 명령 오타)가 빈 문자열로 조용히 흡수된다.
2. **치환 후**: `Select-String -Pattern '\$\{'`로 렌더링된 파일에 남은 플레이스홀더를 찾는다. 목록에 없는 신규 플레이스홀더(오타·변수명 변경 누락)를 잡는 용도로, 1단계와 역할이 겹치지 않는다.

두 검사 중 하나만 있으면 통과하는 실패 조합이 존재하므로, 어느 한쪽도 생략하지 않는다.

## 왜 CloudShell 단계를 그 위치에 두는가

module-4 런북은 CloudShell 작업을 흐름 중간(3단계, 워커 이미지 build/push)과 끝(7단계, kubectl 접근 확인 + 자가 채점)에 나눠 배치한다.

- **중간 배치(3단계)**: EKS 클러스터 생성(eksctl, ~15-20분)은 본 PC가 대기만 하는 시간이다. 이 대기 구간에 CloudShell에서 이미지 빌드·ECR push를 병렬로 끝내면 전체 소요 시간이 두 작업의 합이 아니라 더 긴 쪽(클러스터 생성)에 수렴한다. 3단계를 클러스터 생성 이후로 미루면 이 병렬성이 사라진다.
- **끝 배치(7단계)**: 채점 스크립트(`mark2-4.sh`)가 CloudShell에서 `kubectl`로 클러스터에 접근하는 것을 전제하므로(과제지 유의사항 11), k8s 리소스 apply가 끝난 뒤에야 CloudShell 쪽 kubectl 접근을 확인하는 것이 의미가 있다. 클러스터 생성 직후(access entry 등록 전)에 먼저 확인하면 `Unauthorized`만 반복해서 보게 된다.

set-07 module-3의 linux 런북에서는 CloudShell 단계를 서두 한 줄로만 언급하고 번호를 건너뛰어, 순서대로 따라가면 이 단계 자체를 빠뜨리는 사고가 났다. set-08의 module-2·module-4 README는 CloudShell 단계도 다른 단계와 같은 번호 자리에 명시적으로 넣어 이 문제를 되풀이하지 않는다.

## 왜 module-2는 CloudShell 단계가 하나뿐인가

module-2는 클러스터가 없고 terraform apply 한 번으로 전체 스택이 끝난다. 치환이 필요한 플레이스홀더 파일도 없다(`SERVICE_URL`은 terraform 참조로 apply 시점에 해석되므로 런북 단계에서 별도 치환이 필요 없다). 그래서 CloudShell 작업은 채점 스크립트(`mark2-2.sh`) 실행 한 단계로 끝난다 — module-4처럼 중간 병렬 작업을 배치할 대상 자체가 없다.
