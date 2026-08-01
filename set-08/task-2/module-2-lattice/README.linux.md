# 본 PC 가 Linux 일 때의 런북 (module-2-lattice)

[README.md](README.md) 의 본 PC 단계를 bash/zsh 겸용으로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계도 자리에 그대로 유지했다.

### 0) IAM 권한 프로브 (대회 시작 직후 1회)

이 모듈은 IAM 리소스를 생성하지 않는다. 프로브는 [module-4 런북 0단계](../module-4-sqs-scaling/README.linux.md)에서 1회만 수행한다 (OS 무관, 1회만).

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
until curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
  "http://${CLIENT_IP}/health" | grep -q 200; do sleep 10; done

curl -s "http://${CLIENT_IP}/health"
# → {"status": "ok", "app": "client"}

curl -s "http://${CLIENT_IP}/v1/client/orders?id=1001"
# → {"client": "ok", "service": {"order_id": "1001", "via": "vpc-lattice"}}
#   (service.order_id=1001, service.via=vpc-lattice 확인)
```

### [CloudShell] 셀프 채점

[README.md](README.md) 3단계 CloudShell 항목 수행.

```bash
# CloudShell 에서 mark/mark2-2.sh 를 git clone 또는 파일 업로드(Actions → Upload file)로 전송 후 실행.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark/mark2-2.sh
bash mark/mark2-2.sh
```

### 4) Teardown

```bash
terraform -chdir=terraform destroy -auto-approve
```
