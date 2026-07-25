# 본 PC 가 Linux 일 때의 런북 (module-1-nosql)

[README.md](README.md) 의 본 PC 단계(1·2·Teardown)를 bash 로 옮긴 것. CloudShell 단계(3)는 README.md 와 동일.

### 1) [본 PC] 배포

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC] 앱 기동 대기 (부팅 + pip 설치 ~2-3분)

```bash
until curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
  "$(terraform output -raw healthcheck_url)" | grep -q 200; do sleep 10; done
```

## Teardown

```bash
cd terraform
terraform destroy -auto-approve
```
