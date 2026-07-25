# 본 PC 가 Linux 일 때의 런북 (module-4-container-logging)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. CloudShell 단계는 README.md 와 동일.

```bash
# ===== 본 PC =====
# apply 전 이름 대조는 README.md 의 본 PC 단계와 동일하다.
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json
cd ..

# CloudShell 반입용 zip (terraform/ 는 넣지 않음 — provider 수백 MB).
# 여러 상위 경로를 한 zip 최상위에 평평하게 담기 위해 staging 후 압축한다.
rm -rf /tmp/m4 && mkdir -p /tmp/m4
cp -r eksctl k8s app ../mark ../provided/Module4-Container-Logging terraform/outputs.json /tmp/m4/
(cd /tmp/m4 && zip -r ~/module-4.zip .)
# → CloudShell(ap-northeast-1) 접속 후 Actions → Upload file 로 ~/module-4.zip 업로드
```
