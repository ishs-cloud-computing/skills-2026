#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
#
# karpenter.sh · lbc.sh 가 만든 것을 되돌린다. 클러스터를 지운 뒤 리전 CloudShell 에서 실행한다.
# 스택이 이미 DELETE_FAILED 여도 그대로 실행하면 된다 — 1·2 단계가 실패 원인을 걷어낸다.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-skills-eks}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"

STACK="Karpenter-${CLUSTER_NAME}"

echo "== 1/3 인스턴스 프로파일"
# Karpenter 가 런타임에 만든다(00-nodeclass.yaml 이 role 만 지정). CFN 소유가 아니라 스택 삭제로
# 안 지워지고, 남아 있으면 KarpenterNodeRole 삭제를 막아 스택이 DELETE_FAILED 로 떨어진다.
for profile in $(aws iam list-instance-profiles \
  --query "InstanceProfiles[?starts_with(InstanceProfileName, '${CLUSTER_NAME}_')].InstanceProfileName" \
  --output text); do
  for role in $(aws iam get-instance-profile --instance-profile-name "${profile}" \
    --query 'InstanceProfile.Roles[].RoleName' --output text); do
    aws iam remove-role-from-instance-profile --instance-profile-name "${profile}" --role-name "${role}"
  done
  aws iam delete-instance-profile --instance-profile-name "${profile}"
  echo "  ${profile} 삭제"
done

echo "== 2/3 컨트롤러 역할"
# 스택 밖에서 만든 역할이 스택 소유 정책 6개를 붙들고 있으면 정책 삭제가 409 로 실패한다.
# 정책 자체는 지우지 않는다 — Karpenter 6개는 스택이 지우고, LBC 정책은 다른 세트와 공유한다.
for role in "KarpenterControllerRole-${CLUSTER_NAME}" "AWSLoadBalancerControllerRole-${CLUSTER_NAME}"; do
  if ! aws iam get-role --role-name "${role}" >/dev/null 2>&1; then
    echo "  ${role} (없음)"
    continue
  fi
  for arn in $(aws iam list-attached-role-policies --role-name "${role}" \
    --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "${role}" --policy-arn "${arn}"
  done
  aws iam delete-role --role-name "${role}"
  echo "  ${role} 삭제"
done

echo "== 3/3 CloudFormation 스택 (노드 역할 · 정책 6개 · 인터럽션 큐 · EventBridge 룰)"
if aws cloudformation describe-stacks --region "${AWS_REGION}" --stack-name "${STACK}" >/dev/null 2>&1; then
  aws cloudformation delete-stack --region "${AWS_REGION}" --stack-name "${STACK}"
  aws cloudformation wait stack-delete-complete --region "${AWS_REGION}" --stack-name "${STACK}"
  echo "  ${STACK} 삭제"
else
  echo "  ${STACK} (없음)"
fi
