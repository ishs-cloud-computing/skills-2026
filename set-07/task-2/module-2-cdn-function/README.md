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
# 0) 이름 대조 — 과제지의 아래 이름이 terraform.tfvars 값과 다르면 tfvars 를 먼저 고친다.
#    버킷 skillsphone-landing-ab-<ACCOUNT_ID> / KVS skillsphone-cdn-ab-config
#    함수 skillsphone-cdn-ab-{req,res}-fn / 캐시 정책 skillsphone-cdn-ab-cache-policy
#    Distribution Comment skillsphone-cdn-ab-distribution
#    쿠키 이름 x-sp-ab 는 policies.tf 와 func/*.js 3곳에 있다 — 바뀌면 같이 고친다.
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
# mark2.sh 는 rm -rf ~/.aws 를 수행한다. 반드시 CloudShell 에서 실행한다.
# Actions → Upload file 로 ../mark/mark2.sh 업로드 후
bash mark2.sh
# 기대 출력: mark.md 2-1 ~ 2-6 기대값과 동일
#   2-2: KVS_KV weight 0.3 / ReqFn ... DEPLOYED cloudfront-js-2.0 true
#   2-6: weight_1_uri /version-b/index.html → weight_0_uri /version-a/index.html → weight_restored 0.3
```

```powershell
# ===== 본 PC — 채점 후 =====
# 2-6 이 KVS weight 를 바꿨다 되돌린다. drift 가 남아 있으면 재-apply 한다.
terraform -chdir=terraform plan
```

## 참고

- 설계 근거: `docs/src/content/docs/setlist/set-07/task-2/deployment.md`
- 채점 항목 ↔ 구현 매핑: 같은 경로의 `mapping.md`
- 함정·미해결 항목: [../NOTES.md](../NOTES.md)
