#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
#
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
# 의 Pod Identity 경로. 리전 CloudShell 에서 karpenter.sh 다음에 실행한다.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-skills-eks}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
LBC_VERSION="${LBC_VERSION:-3.5.0}"

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
CONTROLLER_ROLE="AWSLoadBalancerControllerRole-${CLUSTER_NAME}"

command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "== 1/4 IAM 정책"
TEMPOUT="$(mktemp)"
curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v${LBC_VERSION}/docs/install/iam_policy.json" >"${TEMPOUT}"
aws iam create-policy --policy-name "${POLICY_NAME}" \
  --policy-document "file://${TEMPOUT}" >/dev/null 2>&1 || echo "  (이미 존재)"

echo "== 2/4 컨트롤러 역할 (Pod Identity)"
aws iam create-role --role-name "${CONTROLLER_ROLE}" \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "pods.eks.amazonaws.com" },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }]
  }' >/dev/null 2>&1 || echo "  (이미 존재)"

aws iam attach-role-policy --role-name "${CONTROLLER_ROLE}" \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "== 3/4 Pod Identity 연결"
aws eks create-pod-identity-association \
  --region "${AWS_REGION}" \
  --cluster-name "${CLUSTER_NAME}" \
  --namespace kube-system \
  --service-account aws-load-balancer-controller \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CONTROLLER_ROLE}" >/dev/null 2>&1 || echo "  (이미 존재)"

echo "== 4/4 helm 설치"
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
# replicaCount=1 — 차트 기본 2. 유휴 EC2 1대 유지가 목적이고, 1이면 차트가 PDB 도 만들지 않아
# 노드 드레인을 막지 않는다. vpcId·서브넷은 넘기지 않는다(IMDS + 서브넷 태그 자동 검색).
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set "clusterName=${CLUSTER_NAME}" \
  --set replicaCount=1 \
  --wait

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
kubectl get ingressclass alb
