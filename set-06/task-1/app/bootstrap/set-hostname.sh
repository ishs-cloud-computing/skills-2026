#!/usr/bin/env bash
# Bottlerocket bootstrap container 로 실행된다(superpowered=true → /.bottlerocket/rootfs
# 에 호스트 루트FS 마운트). 부팅 시 IMDS 로 instance-id 를 읽어 kubelet 노드명을
# gj2026.<instance_id>.<role>.node 로 설정한다(채점 4-3). <role> 은 bootstrap container
# 의 user-data(base64)로 전달된 값("app" 또는 "addon")이다.
set -euo pipefail

ROLE="$(cat /.bottlerocket/bootstrap-containers/current/user-data)"

TOKEN="$(curl -sS -X PUT 'http://169.254.169.254/latest/api/token' \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')"
IID="$(curl -sS -H "X-aws-ec2-metadata-token: ${TOKEN}" \
  'http://169.254.169.254/latest/meta-data/instance-id')"

# 호스트의 apiclient 로 설정 변경 → Bottlerocket 이 설정을 재렌더링한 뒤 kubelet 기동
chroot /.bottlerocket/rootfs apiclient set \
  "kubernetes.hostname-override=gj2026.${IID}.${ROLE}.node"
