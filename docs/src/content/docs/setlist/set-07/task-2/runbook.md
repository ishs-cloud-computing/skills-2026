---
title: 배포 런북
description: 7세트 2과제 모듈별 배포·채점·teardown 절차
sidebar:
  order: 2
---

모듈은 서로 독립이라 순서 없이 배포한다. 본 PC 단계는 **PowerShell 7 기준**(대회 환경 Windows 11), 채점은 CloudShell(bash). 저장소 `set-07/task-2/` 각 모듈 README와 동일한 절차이며, 본 PC가 Linux면 각 모듈의 README.linux.md를 따른다.

## 모듈 1 — NoSQL (ap-southeast-1)

### 1) [본 PC·PowerShell] 배포

```powershell
cd set-07/task-2/module-1-nosql/terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] 앱 기동 대기 (부팅 + pip 설치 ~2-3분)

```powershell
$URL = terraform output -raw healthcheck_url
while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 $URL) -ne "200") { Start-Sleep 10 }
```

### 3) [CloudShell] 셀프 채점 (1-6-A 는 sleep 30×2 로 약 70초 소요)

```bash
bash mark/mark1.sh
```

### Teardown [본 PC·PowerShell]

```powershell
cd set-07/task-2/module-1-nosql/terraform
terraform destroy -auto-approve
```

## 모듈 2 — CDN Function (us-east-1)

### 1) [본 PC·PowerShell] 배포 (distribution 배포 대기 포함 ~5-7분)

```powershell
cd set-07/task-2/module-2-cdn-function/terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] A/B 동작 검증

```powershell
$URL = terraform output -raw landing_url
# 쿠키 강제: 해당 버전 본문 + Set-Cookie 없음이 기대 출력
curl.exe -si -b "x-sp-ab=a" $URL | Select-String "version-badge|set-cookie"
curl.exe -si -b "x-sp-ab=b" $URL | Select-String "version-badge|set-cookie"
# 첫 방문: Set-Cookie x-sp-ab=<a|b>; Path=/; Max-Age=86400 + 해당 버전 본문이 기대 출력
curl.exe -si $URL | Select-String "version-badge|set-cookie"
```

### 3) [CloudShell] 셀프 채점 (2-6-A 는 KVS 전파 대기로 최대 ~2분)

```bash
bash mark/mark2.sh
```

### Teardown [본 PC·PowerShell]

```powershell
cd set-07/task-2/module-2-cdn-function/terraform
terraform destroy -auto-approve
```
