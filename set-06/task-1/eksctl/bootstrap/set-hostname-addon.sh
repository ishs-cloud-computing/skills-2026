#!/usr/bin/env bash
# plan.md §3.5.1 — 노드명 gj2026.<instance_id>.addon.node (채점 4-3)
# bootstrap container 는 kubelet 이전에 실행되므로 hostname-override 를 선반영할 수 있다.
# provider-id 를 함께 설정해야 external CCM 이 노드↔EC2 매칭에 성공한다 (NotReady 방지).
set -euo pipefail

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 600")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

# 키에 하이픈이 있어 dotted 형식이 아닌 --json 형식을 써야 한다
apiclient set --json "{\"settings\":{\"kubernetes\":{
  \"hostname-override\":\"gj2026.${IID}.addon.node\",
  \"provider-id\":\"aws:///${AZ}/${IID}\"}}}"
