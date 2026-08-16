# 본 PC 가 Linux 일 때의 런북 (module-2-cdn-function)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계(3)도 자리에 stub 으로 표시했다.

### 1) [본 PC] 배포 (distribution 배포 대기 포함 ~5-7분)

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [CloudShell] A/B 동작 검증

[README.md](README.md) 2단계 수행.

### 3) [CloudShell] 셀프 채점

[README.md](README.md) 3단계 수행.

## Teardown

```bash
cd terraform
terraform destroy -auto-approve
```
