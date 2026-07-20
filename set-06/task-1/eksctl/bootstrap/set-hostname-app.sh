#!/usr/bin/env bash
# plan.md §3.5.1 — 노드명 gj2026.<instance_id>.app.node (채점 4-3)
set -euo pipefail

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 600")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

apiclient set --json "{\"settings\":{\"kubernetes\":{
  \"hostname-override\":\"gj2026.${IID}.app.node\",
  \"provider-id\":\"aws:///${AZ}/${IID}\"}}}"
