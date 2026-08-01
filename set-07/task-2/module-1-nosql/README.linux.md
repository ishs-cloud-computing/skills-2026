# 본 PC 가 Linux 일 때의 런북 (module-1-nosql)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계(3)도 자리에 stub 으로 표시했다.

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

### 3) [CloudShell] 셀프 채점

[README.md](README.md) 3단계 수행.

## Teardown

```bash
cd terraform
terraform destroy -auto-approve
```
