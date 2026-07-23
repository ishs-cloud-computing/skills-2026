# 본 PC 가 Linux 일 때의 런북 (module-4-container-logging)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. bastion/CloudShell 단계는 README.md 와 동일.

```bash
# ===== 본 PC =====
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json

# bastion 전송 (terraform/ 는 보내지 않음 — provider 수백 MB. 비밀번호 Skill53##)
BIP=$(terraform output -raw bastion_public_ip)
ssh ec2-user@"$BIP" "mkdir -p ~/module-4"
rsync -az ../eksctl ../k8s ../app ../../mark ../../provided/Module4-Container-Logging outputs.json "ec2-user@${BIP}:~/module-4/"
ssh ec2-user@"$BIP"
```
