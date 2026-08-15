#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
#
# https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/ 의 Pod Identity 경로를
# eksctl 통합 없이 aws CLI 로 옮긴 것. 리전 CloudShell 에서 실행한다.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-skills-eks}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
KARPENTER_VERSION="${KARPENTER_VERSION:-1.14.0}"
KARPENTER_NAMESPACE="${KARPENTER_NAMESPACE:-kube-system}"

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CONTROLLER_ROLE="KarpenterControllerRole-${CLUSTER_NAME}"
NODE_ROLE="KarpenterNodeRole-${CLUSTER_NAME}"

command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "== 1/5 CloudFormation: 노드 역할 · 컨트롤러 정책 6개 · 인터럽션 큐 · EventBridge 룰"
TEMPOUT="$(mktemp)"
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" >"${TEMPOUT}"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

echo "== 2/5 컨트롤러 역할 (Pod Identity)"
aws iam create-role --role-name "${CONTROLLER_ROLE}" \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "pods.eks.amazonaws.com" },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }]
  }' >/dev/null 2>&1 || echo "  (이미 존재)"

for policy in NodeLifecycle IAMIntegration EKSIntegration Interruption ResourceDiscovery ZonalShift; do
  aws iam attach-role-policy --role-name "${CONTROLLER_ROLE}" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterController${policy}Policy-${CLUSTER_NAME}"
done

aws eks create-pod-identity-association \
  --region "${AWS_REGION}" \
  --cluster-name "${CLUSTER_NAME}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --service-account karpenter \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CONTROLLER_ROLE}" >/dev/null 2>&1 || echo "  (이미 존재)"

echo "== 3/5 노드 역할 access entry"
# 공식 문서는 eksctl create iamidentitymapping(aws-auth)을 쓰지만, 본 PC 외에 eksctl 을 두지 않으므로
# 같은 목적의 access entry 로 대신한다. Karpenter 노드는 self-managed EC2 라 EC2_LINUX 다(EC2 는 Auto Mode 전용).
aws eks create-access-entry \
  --region "${AWS_REGION}" \
  --cluster-name "${CLUSTER_NAME}" \
  --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${NODE_ROLE}" \
  --type EC2_LINUX >/dev/null 2>&1 || echo "  (이미 존재)"

echo "== 4/5 클러스터 SG 에 discovery 태그"
# k8s/00-nodeclass.yaml 의 securityGroupSelectorTerms 가 이 태그로 SG 를 찾는다.
CLUSTER_SG="$(aws eks describe-cluster --region "${AWS_REGION}" --name "${CLUSTER_NAME}" \
  --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)"
aws ec2 create-tags --region "${AWS_REGION}" --resources "${CLUSTER_SG}" \
  --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}"

echo "== 5/5 helm 설치"
helm registry logout public.ecr.aws >/dev/null 2>&1 || true
# 공식 명령과 다른 두 곳:
#   replicas=1  — 차트 기본 2 + hostname podAntiAffinity 라 2번째 replica 가 Pending 이 되어
#                 Karpenter 가 자기 자신을 위한 노드를 띄운다. 유휴 EC2 1대가 비용 ratio 의 전제다.
#   resources   — 공식 명령의 cpu=1/memory=1Gi 를 넘기지 않는다(차트 기본 {}). t3.medium 1대에서
#                 1 vCPU 예약은 앱 3종이 들어갈 자리를 없앤다.
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set replicas=1 \
  --wait

kubectl -n "${KARPENTER_NAMESPACE}" rollout status deploy/karpenter
kubectl get crd nodepools.karpenter.sh ec2nodeclasses.karpenter.k8s.aws
