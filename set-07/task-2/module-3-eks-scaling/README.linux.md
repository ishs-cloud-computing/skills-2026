# 본 PC 가 Linux 일 때의 런북 (module-3-eks-scaling)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. CloudShell 단계는 README.md 와 동일.

```bash
# ===== 본 PC =====
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json
cd ..

# CloudShell 반입용 zip (terraform/ 는 넣지 않음 — provider 수백 MB).
# 여러 상위 경로를 한 zip 최상위에 평평하게 담기 위해 staging 후 압축한다.
rm -rf /tmp/m3 && mkdir -p /tmp/m3
cp -r eksctl k8s ../mark ../provided/Module3-EKS-Scaling terraform/outputs.json /tmp/m3/
(cd /tmp/m3 && zip -r ~/module-3.zip .)
# → CloudShell(ap-northeast-2) 접속 후 Actions → Upload file 로 ~/module-3.zip 업로드
```
