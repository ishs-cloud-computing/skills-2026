# 본 PC 가 Linux 일 때의 런북 (module-2-cdn-function)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. CloudShell 채점 단계는 README.md 와 동일.

```bash
# ===== 본 PC =====
# apply 전 이름 대조는 README.md 의 0) 단계와 동일하다.
cd terraform
terraform init
terraform apply -auto-approve        # Distribution 배포 완료(Deployed)까지 약 5~10분

D=$(terraform output -raw distribution_domain)
curl -s -b "x-sp-ab=a" "https://$D/" | grep -o version_a | head -1    # version_a
curl -s -b "x-sp-ab=b" "https://$D/" | grep -o version_b | head -1    # version_b
curl -s -i "https://$D/" | grep -i '^set-cookie:'                     # x-sp-ab=<a|b>; Path=/; Max-Age=86400
```
