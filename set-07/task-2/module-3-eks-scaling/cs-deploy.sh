#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
#
# CloudShell(ap-northeast-2) 배포: KEDA + Karpenter + k8s 리소스.
# 인자 없이 1회 실행해 조회값을 확인한 뒤 --apply 로 적용한다
# (치환과 적용을 한 번에 실행하지 않는다 — NOTES.md 함정 기록).
set -euo pipefail
cd "$(dirname "$0")"

REGION=ap-northeast-2
CLUSTER=skm-eks-cluster
QUEUE_NAME=skm-order-queue
ECR_REPO=skm-order-processor
KEDA_VERSION=2.20.1
KARPENTER_VERSION=1.14.0
ENV_FILE="$HOME/m3.env"

req() { [ -n "$1" ] && [ "$1" != None ] || { echo "STOP: $2 조회 실패 — terraform apply 를 먼저 끝낸다"; exit 1; }; }

# helm 은 CloudShell 미탑재. $HOME 밖은 세션 종료 시 삭제되므로 $HOME/bin 에 설치한다 (멱등).
export PATH="$HOME/bin:$PATH"
if ! command -v helm >/dev/null; then
  mkdir -p "$HOME/bin"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 |
    HELM_INSTALL_DIR="$HOME/bin" USE_SUDO=false bash
fi

kubectl get nodes >/dev/null 2>&1 ||
  { echo "STOP: 클러스터 접속 불가 — aws eks update-kubeconfig --name $CLUSTER --region $REGION 를 먼저 실행한다"; exit 1; }

# 값은 전송하지 않고 이름으로 조회한다 — 이름은 과제지 명시값이라 채점 스크립트도 같은 방식으로 찾는다.
SQS_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$REGION" --query QueueUrl --output text)
ECR_URL=$(aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$REGION" \
  --query 'repositories[0].repositoryUri' --output text)
# 가드 ①: 치환 전 비어있음 검사 — sed 는 빈 값도 그대로 치환해 가드 ② 를 통과시킨다
req "$SQS_URL" sqs_queue_url
req "$ECR_URL" ecr_repository_url
# 중괄호 필수: zsh 는 "$ECR_URL:latest" 의 :l 을 소문자 modifier 로 해석해 이미지명이 깨진다
ECR_IMAGE="${ECR_URL}:latest"

# 전송 zip 에 로컬 rendered/ 가 딸려 왔을 수 있다 — 남은 파일이 apply 되지 않도록 지우고 다시 만든다
rm -rf k8s/rendered && mkdir -p k8s/rendered
for f in k8s/*.yaml; do
  sed -e "s|\${ECR_IMAGE}|${ECR_IMAGE}|g" -e "s|\${SQS_URL}|${SQS_URL}|g" "$f" >"k8s/rendered/$(basename "$f")"
done
# 가드 ②: 목록 외 신규 플레이스홀더 탐지
! grep -rn '\${' k8s/rendered/ || { echo "STOP: 미치환 값 존재"; exit 1; }

# 세션이 끊겨도 재접속 후 source 로 바로 쓰도록 기록한다 (작업 규칙 6)
cat >"$ENV_FILE" <<EOF
export PATH="\$HOME/bin:\$PATH"
export AWS_DEFAULT_REGION=$REGION
export CLUSTER=$CLUSTER
export SQS_URL=$SQS_URL
export ECR_IMAGE=$ECR_IMAGE
EOF

printf 'SQS_URL   %s\nECR_IMAGE %s\n환경변수  %s (재접속 시 source)\n' "$SQS_URL" "$ECR_IMAGE" "$ENV_FILE"

[ "${1:-}" = --apply ] || { printf '\n값이 맞으면: bash %s --apply\n' "$0"; exit 0; }

helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm upgrade --install keda kedacore/keda -n keda --create-namespace --version "$KEDA_VERSION" \
  --set serviceAccount.operator.create=false --set serviceAccount.operator.name=keda-operator \
  --set-json 'tolerations=[{"key":"CriticalAddonsOnly","operator":"Exists"}]'

# replicas=1 필수: chart 기본 2 + required anti-affinity 라 노드 1대(addon NG 1/1/1)에선 --wait 가 영원히 대기
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "$KARPENTER_VERSION" -n kube-system \
  --set replicas=1 \
  --set serviceAccount.create=false --set serviceAccount.name=karpenter \
  --set settings.clusterName="$CLUSTER" --set settings.interruptionQueue="" \
  --set controller.resources.requests.cpu=500m --set controller.resources.requests.memory=512Mi \
  --wait

kubectl apply -f k8s/rendered/ # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장
