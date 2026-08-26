# ECR 강화 부착 KIT

기존 리포지토리에 scan on push · 불변 태그(예외 필터) · CMK 암호화를 붙이고, lifecycle policy와 pull-through cache를 새 리소스로 붙인다.

## 이 KIT이 맞나

- 과제지 기존 ECR 문항 뒤에 **"이미지 스캔"·"태그 불변성"·"lifecycle policy"·"pull-through cache"** 가 붙었다 → 맞다.
- **CMK 암호화만** → [kms](../kms/README.md) 4번 블록과 같다. 둘 다 **재생성**이라는 점이 핵심이다.

## 세트별 현재 리포지토리 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 리소스 | `aws_ecr_repository.book` | `aws_ecr_repository.book` | `aws_ecr_repository.app` |
| 이름 | `var.ecr_repo_name` | `var.ecr_name` | `"unicorn-concert-app"` (하드코딩) |
| scan on push | 켜짐 | 켜짐 | 켜짐 |
| 태그 불변성 | **미설정**(MUTABLE) | `MUTABLE_WITH_EXCLUSION` + `v1*` | `IMMUTABLE_WITH_EXCLUSION` + `latest` |
| 암호화 | `KMS` (AWS 관리 `aws/ecr`) | `KMS` + `aws_kms_key.ecr` | `KMS` + `aws_kms_key.data` |
| `force_delete` | 켜짐 | 켜짐 | 켜짐 |
| lifecycle policy | **없음** | **없음** | **없음** |
| URL output | `ecr_repository_url` | `ecr_repository_url` | `ecr_repository_url` |

세 세트 모두 URL output이 이미 있다:

```powershell
terraform output -raw ecr_repository_url
# → 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/<리포이름>
```

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `ecr.tf` | `set-XX/task-1/terraform/ecr-addon.tf` (**기존 `ecr.tf` 와 이름이 겹친다**) | `aws_ecr_lifecycle_policy` · `aws_ecr_pull_through_cache_rule` |
| `variables.tf` | `variables-ecr-addon.tf` | `addon_ecr_*` 변수 |

스캔·불변 태그·암호화는 파일이 아니라 기존 `aws_ecr_repository` 안에 넣는 **블록**이다.

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_ecr_repository_name` | **필수** | lifecycle 대상 리포 이름. 같은 루트면 `aws_ecr_repository.<기존>.name` 직접 참조 |
| `addon_ecr_untagged_expire_days` | `1` | untagged 이미지 만료 일수 |
| `addon_ecr_keep_image_count` | `10` | 유지할 태그 이미지 개수 |
| `addon_ecr_keep_tag_prefixes` | `[]` | `["v"]` 면 `v*` 태그만 개수 제한 |
| `addon_ecr_pull_through_upstreams` | `{}` | `{prefix = upstream URL}`. 빈 맵이면 생성 안 함 |

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_ecr_repository_name      = "skills-app"
addon_ecr_untagged_expire_days = 1
addon_ecr_keep_image_count     = 10
addon_ecr_keep_tag_prefixes    = []
addon_ecr_pull_through_upstreams = {}   # 과제에 없으면 비워 둔다
```

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # 기존 리포지토리에 must be replaced 가 뜨는지 반드시 본다
terraform apply
```

## FAST — terraform 없이 CLI 로 붙이기

채점은 **관찰 가능한 상태**만 본다. 스캔·태그 불변·lifecycle 은 전부 in-place 다.

**대가**: terraform state 와 실물이 어긋난다. 이 세트에 이후 `apply` 를 걸면 되돌아가므로,
CLI 로 붙였으면 그 세트는 더 apply 하지 않거나 나중에 같은 값을 `.tf` 에도 넣는다.

```powershell
$R = '<리포>'

aws ecr put-image-scanning-configuration --repository-name $R `
  --image-scanning-configuration scanOnPush=true

aws ecr put-image-tag-mutability --repository-name $R --image-tag-mutability IMMUTABLE

@'
{"rules":[{"rulePriority":1,"description":"keep last 10",
  "selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},
  "action":{"type":"expire"}}]}
'@ | Set-Content -Encoding utf8 ecr-lifecycle.json
aws ecr put-lifecycle-policy --repository-name $R --lifecycle-policy-text file://ecr-lifecycle.json
```

- **CMK 암호화는 생성 시에만** 지정된다. 이미 만든 리포지토리는 CLI 로도 못 바꾼다 → [3. CMK 암호화](#3-cmk-암호화-재생성) 의 재생성 비용을 먼저 계산한다.
- 태그 불변으로 바꾸면 **같은 태그 재push 가 거부된다.** 앱 배포에 `:latest` 를 쓰고 있으면 먼저 태그 전략부터 바꾼다.

## 1. push 시 취약점 스캔

```hcl
# 파일: set-XX/task-1/terraform/ecr.tf
# 기존 aws_ecr_repository 리소스 블록 *안에* (in-place)
image_scanning_configuration {
  scan_on_push = true
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**세 세트 모두 이미 켜져 있다.** 중복 선언하면 `Duplicate block` 오류다 — 확인만 한다.

```powershell
$repo = (terraform output -raw ecr_repository_url).Split('/')[-1]
aws ecr describe-repositories --repository-names $repo `
  --query "repositories[].imageScanningConfiguration"

aws ecr describe-image-scan-findings --repository-name $repo --image-id imageTag=latest `
  --query "imageScanFindings.findingSeverityCounts"
```
</details>

## 2. 태그 불변 + 예외 필터

```hcl
# 파일: set-XX/task-1/terraform/ecr.tf
# 기존 aws_ecr_repository 리소스 블록 *안에* (in-place, provider 6.8.0+)
# "latest 만 덮어쓰기 허용" → IMMUTABLE_WITH_EXCLUSION + latest
# "v1* 만 불변"            → MUTABLE_WITH_EXCLUSION + v1*
image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
image_tag_mutability_exclusion_filter {
  filter      = "latest"
  filter_type = "WILDCARD"     # WILDCARD 만 허용
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 현재 | 과제지가 "불변"을 요구하면 |
| --- | --- | --- |
| set-02 | 미설정 (MUTABLE) | 위 블록을 **새로 추가**. 런북이 `latest` 를 두 번 push하면 예외 필터에 `latest` 필수 |
| set-03 | `MUTABLE_WITH_EXCLUSION` + `v1*` | 기존 블록의 `filter` 만 바꾼다 |
| set-07 | `IMMUTABLE_WITH_EXCLUSION` + `latest` | 그대로 |

```powershell
$repo = (terraform output -raw ecr_repository_url).Split('/')[-1]
aws ecr describe-repositories --repository-names $repo `
  --query "repositories[].[imageTagMutability,imageTagMutabilityExclusionFilters]"
```

`IMMUTABLE` 에서 같은 태그 재 push는 `ImageTagAlreadyExistsException`. 예외 필터는 **최대 5개**.
</details>

## 3. CMK 암호화 (**재생성**)

```hcl
# 파일: set-XX/task-1/terraform/ecr.tf
# 기존 aws_ecr_repository 리소스 블록 *안에* — 기존 리포는 재생성된다
encryption_configuration {
  encryption_type = "KMS"
  kms_key         = aws_kms_key.addon.arn   # 생략하면 AWS 관리 aws/ecr 키
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 현재 키 | 키 ARN output |
| --- | --- | --- |
| set-02 | AWS 관리 `aws/ecr` (`kms_key` 생략) | — . **CMK 이름이 과제지에 없으면 일부러 생략한 것**이다 (불필요 리소스 감점 회피) |
| set-03 | `aws_kms_key.ecr` | `ecr_kms_arn` (**이미 있음**) |
| set-07 | `aws_kms_key.data` | `data_kms_arn` (**이미 있음**) |

```powershell
terraform output -raw ecr_kms_arn      # set-03
terraform output -raw data_kms_arn     # set-07
```

**재생성되면 push한 이미지가 전부 사라진다.** apply 후 반드시 다시 빌드·푸시하고 롤아웃한다:

```powershell
$url = terraform output -raw ecr_repository_url
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $url.Split('/')[0]
docker build -t "${url}:latest" .
docker push "${url}:latest"
kubectl rollout restart deployment/<앱> -n <ns>
```

`terraform plan` 에 `must be replaced` 가 뜨는지 반드시 확인하고, 시간 대비 배점을 보고 결정한다.
</details>

## 4. lifecycle policy

```hcl
# 파일: set-XX/task-1/terraform/ecr-addon.tf   (KIT에서 복사됨)
resource "aws_ecr_lifecycle_policy" "addon" {
  repository = aws_ecr_repository.book.name    # ← 세트별 주소로 치환

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "expire untagged"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = var.addon_ecr_untagged_expire_days }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2                        # tagStatus=any 는 항상 마지막
        description  = "keep last N"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.addon_ecr_keep_image_count }
        action       = { type = "expire" }
      },
    ]
  })
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

세 세트 모두 lifecycle policy가 **없다** — 새로 만든다. 리포당 1개이므로 충돌은 없다.

| 세트 | `repository` 에 넣을 값 |
| --- | --- |
| set-02 | `aws_ecr_repository.book.name` |
| set-03 | `aws_ecr_repository.book.name` |
| set-07 | `aws_ecr_repository.app.name` |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "ecr_repository_name" {
  value = aws_ecr_repository.book.name      # set-07 은 aws_ecr_repository.app.name
}
```

```powershell
$repo = terraform output -raw ecr_repository_name
aws ecr get-lifecycle-policy --repository-name $repo --query lifecyclePolicyText --output text

# 실제로 뭐가 지워질지 미리보기 (평가는 비동기라 apply 직후엔 안 지워진다)
aws ecr start-lifecycle-policy-preview --repository-name $repo
aws ecr get-lifecycle-policy-preview --repository-name $repo --query "previewResults[].[imageTags,action.type]"
```

`tagStatus = any` 규칙은 `rulePriority` 가 가장 커야 한다. `tagPatternList`(`v*` 와일드카드)는 `tagPrefixList` 와 배타 — 과제지가 와일드카드를 요구하면 키를 바꾼다(둘 동시 지정은 거부).
</details>

## 5. pull-through cache

```hcl
# 파일: set-XX/task-1/terraform/ecr-addon.tf   (KIT에서 복사됨)
resource "aws_ecr_pull_through_cache_rule" "addon" {
  for_each              = var.addon_ecr_pull_through_upstreams
  ecr_repository_prefix = each.key
  upstream_registry_url = each.value
}
```

```hcl
# 파일: set-XX/task-1/terraform/terraform.tfvars
addon_ecr_pull_through_upstreams = {
  ecr-public      = "public.ecr.aws"
  quay            = "quay.io"
  registry-k8s-io = "registry.k8s.io"
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

task-1 세 세트에는 pull-through cache가 **없다**. 완성 원본은 **set-05 task-1 `terraform/ecr.tf`** 다 (3종 + 미러 리포).

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "ecr_registry" {
  value = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}
```

```powershell
terraform output -raw ecr_registry
aws ecr describe-pull-through-cache-rules `
  --query "pullThroughCacheRules[].[ecrRepositoryPrefix,upstreamRegistryUrl]" --output table

# 노드/Pod 가 pull 하는 주소 형태
"$(terraform output -raw ecr_registry)/ecr-public/<이미지>:<태그>"
```

- **prefix는 계정·리전 내 유일**하다.
- 첫 pull 때 리포가 자동 생성된다 — pull 주체 Role에 `ecr:BatchImportUpstreamImage`·`ecr:CreateRepository` 가 필요하다 (노드 기본 `AmazonEC2ContainerRegistryReadOnly` 에는 없다).
- Docker Hub(`registry-1.docker.io`)·GHCR은 Secrets Manager 자격증명이 필수라 익명 pull이 안 된다.
</details>

## VERIFY

```powershell
$repo = (terraform output -raw ecr_repository_url).Split('/')[-1]
aws ecr describe-repositories --repository-names $repo `
  --query "repositories[].[imageTagMutability,imageScanningConfiguration.scanOnPush,encryptionConfiguration]"
aws ecr get-lifecycle-policy --repository-name $repo --query lifecyclePolicyText --output text
aws ecr list-images --repository-name $repo --query "imageIds[].imageTag"
```

## TROUBLESHOOT

- **`encryption_configuration` 은 재생성이다** — 이미지 전부 소실, 재 push 필요. `plan` 에서 `must be replaced` 를 반드시 확인한다.
- `IMMUTABLE` 에서 같은 태그 재 push는 `ImageTagAlreadyExistsException`. 예외 필터 최대 5개, `WILDCARD` 만.
- lifecycle policy는 **리포당 1개** — 이미 있으면 덮어쓴다. 평가는 비동기(보통 24시간 이내)라 apply 직후 이미지가 안 지워진다. 채점은 정책 텍스트를 본다.
- `tagStatus = any` 규칙은 `rulePriority` 가 가장 커야 한다.
- 레지스트리 레벨 ENHANCED 스캔(`aws_ecr_registry_scanning_configuration`)은 **계정당 1개**라 KIT에 없다. ENHANCED로 바꾸면 `scan_on_push` 는 무시되고 레지스트리 규칙이 우선한다.
- `force_delete = true` 가 없으면 이미지가 있는 리포는 destroy가 실패한다 (세 세트 모두 이미 켜져 있다).

## 실전 구현 (참고용)

- set-07 task-1 `terraform/ecr.tf` — `IMMUTABLE_WITH_EXCLUSION latest` · scan · CMK
- set-03 task-1 `terraform/ecr.tf` — `MUTABLE_WITH_EXCLUSION v1*`
- set-02 task-1 `terraform/ecr.tf` — AWS 관리 키로 `encryption_type = "KMS"` 만 (CMK 이름 미지정 시 패턴)
- set-05 task-1 `terraform/ecr.tf` — pull-through cache 3종 · 미러 리포
- lifecycle policy는 실전 구현이 없다.

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
