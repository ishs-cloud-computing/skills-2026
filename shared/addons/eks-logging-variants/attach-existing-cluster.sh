#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
# 기존 클러스터에 Control Plane 로깅 · Secret envelope CMK · 로그 그룹 CMK 를 부착한다.
# 재생성 없음. 필요한 항목만 남기고 실행한다. (CloudShell / Git Bash)
set -euo pipefail

CLUSTER="${CLUSTER:-skills-eks}"
REGION="${REGION:-ap-northeast-2}"
KMS_ARN="${KMS_ARN:?terraform output -raw addon_ekslog_kms_arn}"

# 1) Control Plane 로그 5종 — 로그 그룹 /aws/eks/<cluster>/cluster 가 없으면 EKS 가 만든다(CMK 없이)
eksctl utils update-cluster-logging --cluster "$CLUSTER" --region "$REGION" --enable-types all --approve

# 2) Secret envelope 암호화 — 한 번 켜면 끌 수 없다. 기존 Secret 도 재암호화된다(수 분)
eksctl utils enable-secrets-encryption --cluster "$CLUSTER" --region "$REGION" --key-arn "$KMS_ARN"

# 3) 이미 생긴 로그 그룹에 CMK 연결 — in-place. key policy 에 logs 서비스 문장이 먼저 있어야 한다
aws logs associate-kms-key --region "$REGION" --log-group-name "/aws/eks/$CLUSTER/cluster" --kms-key-id "$KMS_ARN"

# 검증
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query '{logging:cluster.logging.clusterLogging[0],encryption:cluster.encryptionConfig[0].provider.keyArn}'
aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "/aws/eks/$CLUSTER/" \
  --query 'logGroups[].{name:logGroupName,kms:kmsKeyId,retention:retentionInDays}'
