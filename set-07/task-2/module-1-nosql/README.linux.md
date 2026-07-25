# 본 PC 가 Linux 일 때의 런북 (module-1-nosql)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. CloudShell 채점 단계는 README.md 와 동일.

```bash
# ===== 본 PC =====
# apply 전 이름 대조는 README.md 의 0) 단계와 동일하다.
cd terraform
terraform init
terraform apply -auto-approve        # 약 2분. EC2 userdata(pip 설치) 완료까지 +2~3분 대기

IP=$(terraform output -raw app_public_ip)
curl -s -o /dev/null -w "%{http_code}\n" "http://${IP}:8080/healthcheck"   # 200
```
