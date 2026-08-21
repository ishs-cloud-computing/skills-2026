# 본 PC 가 Linux 일 때의 런북 (module-2-lattice)

[README.md](README.md) 의 본 PC 단계를 bash/zsh 겸용으로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계도 자리에 그대로 유지했다.

### 1) 배포

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

### 2) 환경변수 (.env)

```bash
export AWS_DEFAULT_REGION=ap-northeast-1
export CLIENT_IP=$(terraform -chdir=terraform output -raw client_public_ip)
export SERVICE_DOMAIN=$(terraform -chdir=terraform output -raw service_domain)
export SERVICE_NETWORK_ID=$(terraform -chdir=terraform output -raw service_network_id)
export SERVICE_ID=$(terraform -chdir=terraform output -raw service_id)
export TARGET_GROUP_ID=$(terraform -chdir=terraform output -raw target_group_id)

cat > .env <<EOF
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
export CLIENT_IP=${CLIENT_IP}
export SERVICE_DOMAIN=${SERVICE_DOMAIN}
export SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}
export SERVICE_ID=${SERVICE_ID}
export TARGET_GROUP_ID=${TARGET_GROUP_ID}
EOF

source .env   # 재접속 시: module-2-lattice 디렉터리에서 `source .env` 만 다시 실행
```

### 3) 검증 (배포 후 ~1-2분 대기: user-data systemd 기동, Client Public IP 경유)

```bash
n=0; until curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
  "http://${CLIENT_IP}/health" | grep -q 200 || [ $n -ge 60 ]; do sleep 10; n=$((n+1)); done   # 상한 10분

curl -s "http://${CLIENT_IP}/health"
# → {"status": "ok", "app": "client"}

# Lattice Target Group의 healthy 전환은 배포 완료 후에도 별도로 ~30-60초 더 걸릴 수 있어
# /health 통과 직후 곧바로 호출하면 502/타임아웃이 날 수 있다 — 재시도 루프로 흡수
n=0; until curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
  "http://${CLIENT_IP}/v1/client/orders?id=1001" | grep -q 200 || [ $n -ge 60 ]; do sleep 10; n=$((n+1)); done   # 상한 10분

curl -s "http://${CLIENT_IP}/v1/client/orders?id=1001"
# → {"client": "ok", "service": {"order_id": "1001", "via": "vpc-lattice"}}
#   (service.order_id=1001, service.via=vpc-lattice 확인)

# 채점 2-2: service EC2 는 Public IP 가 없어야 한다
aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],PublicIp:PublicIpAddress,State:State.Name}' --output table

# 채점 2-4: Target Status=HEALTHY 는 독립 합격 기준이다. 셀프 채점 전에 반드시 확인한다
TG=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text)
n=0; until [ "$(aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TG" --query 'items[0].status' --output text)" = "HEALTHY" ] || [ $n -ge 60 ]; do sleep 10; n=$((n+1)); done   # 상한 10분. $TG 가 None 이면 영원히 안 돈다
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TG" --query 'items[].{Target:id,Port:port,Status:status}' --output table
# → Status=HEALTHY. UNUSED/UNHEALTHY 상태로 mark2-2.sh 를 돌리면 2-5 는 통과해도 2-4 를 잃는다
```

### [CloudShell] 셀프 채점

[README.md](README.md) 3단계 CloudShell 항목 수행.

```bash
# mark/mark2-2.sh 를 CloudShell 에 업로드(작업 → 파일 업로드) 후 실행. 저장소가 private 이라 git clone 은 쓰지 않는다.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark2-2.sh
bash mark2-2.sh
```

### 4) Teardown

```bash
terraform -chdir=terraform destroy -auto-approve
```

1회차가 `unexpected state 'UNUSED', wanted target ''` (Lattice Target Group Attachment)로 실패한다.
**[실측 2026-08-21] 재시도로는 해결되지 않는다** — AWS 쪽은 이미 해제됐고(프로바이더 waiter 가 target 이
아니라 TG 상태를 보는 버그) state 에서 떼어내야 한다.

```bash
TG=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text)   # 새 셸이면 재유도
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TG" --output table
# → items 가 비어 있으면 AWS 쪽은 이미 해제된 것이다. 비어 있지 않으면 state rm 하지 마라 — 다른 원인이다

terraform -chdir=terraform state rm aws_vpclattice_target_group_attachment.service
terraform -chdir=terraform destroy -auto-approve
```

teardown 이 막혔다고 리소스가 남은 게 아니다. 콘솔에서 수동 삭제하지 마라.
