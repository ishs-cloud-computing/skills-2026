# Module 2 — CDN Function (us-east-1)

CloudFront + CloudFront Functions(KVS) + S3(OAC) 엣지 A/B 테스팅. terraform 만으로 배포한다.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다 (CloudShell 단계는 공통).

## 디렉토리 구조

```
module-2-cdn-function/
└── terraform/
    ├── versions.tf variables.tf terraform.tfvars data.tf
    ├── s3.tf               # 랜딩 버킷 + 오브젝트 2개 + OAC 전용 버킷 정책
    ├── kvs.tf              # KeyValueStore (weight/version_a/version_b)
    ├── functions.tf        # CF Functions 2개 (LIVE 발행, req-fn 은 KVS 연결)
    ├── func/ab-request.js  # A/B 배정 + URI 재작성 (직접 작성)
    ├── func/ab-response.js # Set-Cookie 부여 (직접 작성)
    ├── policies.tf         # 커스텀 캐시/보안헤더 정책
    └── cloudfront.tf       # OAC + Distribution (Comment 로 식별)

# 랜딩 페이지: ../provided/Module2-CDN-Function/index_{a,b}.html (제공 파일, 수정 금지)
# 채점: ../mark/mark2.sh (CloudShell 에서 실행)
```

## 배포 순서

```powershell
# ===== 본 PC =====
cd terraform
terraform init
terraform apply -auto-approve        # Distribution 배포 완료(Deployed)까지 약 5~10분

$D = terraform output -raw distribution_domain
curl.exe -s -b "x-sp-ab=a" "https://$D/" | Select-String version_a    # version_a 포함
curl.exe -s -b "x-sp-ab=b" "https://$D/" | Select-String version_b    # version_b 포함
curl.exe -s -i "https://$D/" | Select-String Set-Cookie               # x-sp-ab=<a|b>; Path=/; Max-Age=86400
```

```bash
# ===== CloudShell (us-east-1) =====
# Actions → Upload file 로 ../mark/mark2.sh 업로드 후
bash mark2.sh
# 기대 출력: mark.md 2-1 ~ 2-6 기대값과 동일
#   2-2: KVS_KV weight 0.3 / ReqFn ... DEPLOYED cloudfront-js-2.0 true
#   2-6: weight_1_uri /version-b/index.html → weight_0_uri /version-a/index.html → weight_restored 0.3
```

## 요구사항 ↔ 구현 매핑 (채점지 2)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 2-1 | 버킷 이름/오브젝트/Public 차단/버킷 정책 | `terraform/s3.tf` |
| 2-2 | KVS 3키 + 함수 2개 LIVE/KVS 연결 | `terraform/kvs.tf`, `functions.tf`, `func/*.js` |
| 2-3 | 캐시 정책/OAC/redirect-to-https/함수 연결 | `terraform/policies.tf`, `cloudfront.tf` |
| 2-4 | 쿠키 강제 시 버전 고정 + Set-Cookie 없음 | `func/ab-request.js`, `func/ab-response.js` |
| 2-5 | 무작위 배정 + 쿠키 보존 | `func/ab-request.js`, `func/ab-response.js` |
| 2-6 | KVS weight 동적 반영 | `func/ab-request.js` (매 호출 `kvs.get`) |

## 주의 / 검증 포인트

- **이름 정확 일치**: 버킷 `skillsphone-landing-ab-<ACCOUNT_ID>`, KVS `skillsphone-cdn-ab-config`, 함수 `skillsphone-cdn-ab-{req,res}-fn`, 캐시 정책 `skillsphone-cdn-ab-cache-policy`, Distribution Comment `skillsphone-cdn-ab-distribution`.
- 버킷 정책은 **Statement 1개만** 둔다 — 채점 2-1 이 `Statement[0]` 만 검사한다.
- 채점 2-6 이 KVS `weight` 를 1.0/0.0 으로 바꿨다가 0.3 으로 복원한다. 채점 후 `terraform plan` 에 KVS drift 가 보이면 복원이 안 된 것이므로 재-apply 한다.
- 함수는 weight 를 **매 호출** KVS 에서 읽는다(캐싱 금지) — 2-6 이 put-key 후 60초 내 반영을 검사한다.
- `x-sp-ab-assigned` 요청 헤더는 **신규 배정 시에만** 설정한다. 쿠키가 있는 요청에 설정하면 2-4 의 no_setcookie 검사가 깨진다.
- mark2.sh 는 `rm -rf ~/.aws` 를 수행하므로 반드시 CloudShell 에서 실행한다.
