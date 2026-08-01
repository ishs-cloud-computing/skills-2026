# Module 2 — CDN Function (us-east-1)

S3(OAC) + CloudFront KeyValueStore + CloudFront Functions(js-2.0) 엣지 A/B 테스팅. 채점은 CloudShell에서 `mark/mark2.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

## 디렉토리 구조

```
module-2-cdn-function/
├── terraform/
│   ├── s3.tf            # 랜딩 버킷 + PAB + index 오브젝트 2개 + OAC 버킷 정책
│   ├── functions.tf     # KVS(키 3개) + viewer-request/response 함수
│   ├── cloudfront.tf    # OAC, cache/response-headers policy, distribution
│   ├── cloudfront/      # req-fn.js, res-fn.js (함수 소스)
│   └── {versions,variables,outputs}.tf
└── README.md

# 정적 콘텐츠: task-2/provided/module-2/{index_a,index_b}.html (제공 원본, 수정 금지) — terraform 이 직접 참조
# 채점: task-2/mark/mark2.sh (CloudShell, us-east-1)
```

## 배포 순서

### 1) [본 PC·PowerShell] 배포 (distribution 배포 대기 포함 ~5-7분)

```powershell
cd terraform
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

## Teardown

### [본 PC·PowerShell]

```powershell
cd terraform
terraform destroy -auto-approve
```
