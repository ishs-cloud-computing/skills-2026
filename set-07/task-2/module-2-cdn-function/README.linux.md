# 본 PC 가 Linux 일 때의 런북 (module-2-cdn-function)

[README.md](README.md) 의 본 PC 단계(1·2·Teardown)를 bash 로 옮긴 것. CloudShell 단계(3)는 README.md 와 동일.

### 1) [본 PC] 배포 (distribution 배포 대기 포함 ~5-7분)

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC] A/B 동작 검증

```bash
URL=$(terraform output -raw landing_url)
# 쿠키 강제: 해당 버전 본문 + Set-Cookie 없음이 기대 출력
curl -si -b "x-sp-ab=a" "$URL" | grep -iE "version-badge|set-cookie"
curl -si -b "x-sp-ab=b" "$URL" | grep -iE "version-badge|set-cookie"
# 첫 방문: Set-Cookie x-sp-ab=<a|b>; Path=/; Max-Age=86400 + 해당 버전 본문이 기대 출력
curl -si "$URL" | grep -iE "version-badge|set-cookie"
```

## Teardown

```bash
cd terraform
terraform destroy -auto-approve
```
