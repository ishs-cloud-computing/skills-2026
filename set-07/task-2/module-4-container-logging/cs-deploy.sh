#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
#
# CloudShell(ap-northeast-1) 배포: LBC + Loki + Grafana + k8s 리소스.
# PLAYER(선수 등번호)를 지정하고, 인자 없이 1회 실행해 조회값을 확인한 뒤 --apply 로 적용한다.
#   PLAYER=01 bash cs-deploy.sh
#   PLAYER=01 bash cs-deploy.sh --apply
set -euo pipefail
cd "$(dirname "$0")"

REGION=ap-northeast-1
CLUSTER=o11y-cluster
NAME_PREFIX=o11y
ECR_REPO=o11y-log-generator
LBC_VERSION=3.4.3
LOKI_VERSION=18.7.1
GRAFANA_VERSION=12.10.0
ENV_FILE="$HOME/m4.env"

req() { [ -n "$1" ] && [ "$1" != None ] || { echo "STOP: $2 조회 실패 — terraform apply 를 먼저 끝낸다"; exit 1; }; }

[ -n "${PLAYER:-}" ] || { echo "STOP: PLAYER 미설정 — 예) PLAYER=01 bash $0"; exit 1; }

# helm 은 CloudShell 미탑재. $HOME 밖은 세션 종료 시 삭제되므로 $HOME/bin 에 설치한다 (멱등).
export PATH="$HOME/bin:$PATH"
if ! command -v helm >/dev/null; then
  mkdir -p "$HOME/bin"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 |
    HELM_INSTALL_DIR="$HOME/bin" USE_SUDO=false bash
fi

kubectl get nodes >/dev/null 2>&1 ||
  { echo "STOP: 클러스터 접속 불가 — aws eks update-kubeconfig --name $CLUSTER --region $REGION 를 먼저 실행한다"; exit 1; }

# 값은 전송하지 않고 이름으로 조회한다 — 이름은 과제지/terraform 고정값이라 재현 가능하다.
ECR_URL=$(aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$REGION" \
  --query 'repositories[0].repositoryUri' --output text)
ALB_SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${NAME_PREFIX}-alb-sg" --query 'SecurityGroups[0].GroupId' --output text)
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Name,Values=${NAME_PREFIX}-vpc" --query 'Vpcs[0].VpcId' --output text)
# 가드 ①: 치환 전 비어있음 검사 — sed 는 빈 값도 그대로 치환해 가드 ② 를 통과시킨다
req "$ECR_URL" ecr_repository_url
req "$ALB_SG_ID" alb_sg_id
req "$VPC_ID" vpc_id
# 중괄호 필수: zsh 는 "$ECR_URL:latest" 의 :l 을 소문자 modifier 로 해석해 이미지명이 깨진다
ECR_IMAGE="${ECR_URL}:latest"

# 전송 zip 에 로컬 rendered/ 가 딸려 왔을 수 있다 — 남은 파일이 apply 되지 않도록 지우고 다시 만든다
rm -rf k8s/rendered && mkdir -p k8s/rendered
for f in k8s/*.yaml; do
  sed -e "s|\${ECR_IMAGE}|${ECR_IMAGE}|g" -e "s|\${ALB_SG_ID}|${ALB_SG_ID}|g" "$f" >"k8s/rendered/$(basename "$f")"
done
# 가드 ②: 목록 외 신규 플레이스홀더 탐지
! grep -rn '\${' k8s/rendered/ || { echo "STOP: 미치환 값 존재"; exit 1; }

# 세션이 끊겨도 재접속 후 source 로 바로 쓰도록 기록한다 (작업 규칙 6)
cat >"$ENV_FILE" <<EOF
export PATH="\$HOME/bin:\$PATH"
export AWS_DEFAULT_REGION=$REGION
export CLUSTER=$CLUSTER
export PLAYER=$PLAYER
export ECR_IMAGE=$ECR_IMAGE
export ALB_SG_ID=$ALB_SG_ID
export VPC_ID=$VPC_ID
EOF

printf 'ECR_IMAGE %s\nALB_SG_ID %s\nVPC_ID    %s\nPLAYER    %s\n환경변수  %s (재접속 시 source)\n' \
  "$ECR_IMAGE" "$ALB_SG_ID" "$VPC_ID" "$PLAYER" "$ENV_FILE"

[ "${1:-}" = --apply ] || { printf '\n값이 맞으면: PLAYER=%s bash %s --apply\n' "$PLAYER" "$0"; exit 0; }

# 05-storageclass 는 Loki PVC 의 전제라 helm 보다 먼저 있어야 한다
kubectl apply -f k8s/rendered/00-namespace.yaml -f k8s/rendered/05-storageclass.yaml

helm repo add eks https://aws.github.io/eks-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update

# region·vpcId 명시: IMDS 자동탐지(hop limit)로 인한 기동 실패 회피
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version "$LBC_VERSION" \
  --set clusterName="$CLUSTER" --set region="$REGION" --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --wait

helm upgrade --install o11y-loki grafana-community/loki -n monitoring --version "$LOKI_VERSION" \
  -f helm/loki-values.yaml --wait

# 비대화형 셸이라 "!" 히스토리 확장이 일어나지 않는다 (붙여넣기 실행 시의 이스케이프 불필요)
helm upgrade --install o11y-grafana grafana-community/grafana -n monitoring --version "$GRAFANA_VERSION" \
  -f helm/grafana-values.yaml \
  --set adminUser="skills${PLAYER}" --set adminPassword="GoodJob!Skills${PLAYER}^^" \
  --set-file dashboards.default.log-overview.json=helm/dashboards/log-overview.json --wait

kubectl apply -f k8s/rendered/ # 00·05 는 재적용(무해), TGB CRD 는 위 LBC 가 제공
