# ecr-hardening 부착 스니펫

기존 ECR 리포지토리에 scan on push·불변 태그(예외 필터)·CMK 암호화를 붙이고,
lifecycle policy(untagged 만료·태그 N개 유지)와 pull-through cache 를 새 리소스로 붙인다.
1과제 ECR 옵션(전 세트 task-1 ECR), set-07 m3, set-08 m4 후보에 대응.

## 파일

- `ecr.tf` — `aws_ecr_lifecycle_policy`(untagged 만료 + 태그 N개 유지) · `aws_ecr_pull_through_cache_rule`(for_each, 선택)
- `variables.tf` — `addon_ecr_*` 변수

리포지토리 안 인자(스캔·불변 태그·암호화)는 tf 파일 없이 아래 "블록" 을 기존 `aws_ecr_repository` 에 붙인다.

## 부착 절차

1. `ecr.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 같은 루트 모듈이면 `var.addon_ecr_repository_name` 을 `aws_ecr_repository.<기존>.name` 으로 바꾼다.

   ```hcl
   addon_ecr_repository_name      = "skills-app"
   addon_ecr_untagged_expire_days = 1
   addon_ecr_keep_image_count     = 10
   addon_ecr_keep_tag_prefixes    = []      # ["v"] 면 v* 태그만 개수 제한
   # pull-through cache 가 과제에 없으면 비워 둔다 (기본값 {})
   addon_ecr_pull_through_upstreams = {
     ecr-public      = "public.ecr.aws"
     quay            = "quay.io"
     registry-k8s-io = "registry.k8s.io"
   }
   ```
3. 아래 "블록" 을 `aws_ecr_repository.<기존>` 안에 붙인다.
4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리포지토리가 `update in-place` 인지(`replace` 없음) 확인 → `terraform apply`. `encryption_configuration` 을 붙였는데 `replace` 가 뜨면 함정 절을 본다.
5. 검증:

   ```powershell
   aws ecr describe-repositories --repository-names <리포> --query 'repositories[].[imageTagMutability,imageScanningConfiguration.scanOnPush,encryptionConfiguration]'
   aws ecr get-lifecycle-policy --repository-name <리포> --query lifecyclePolicyText --output text
   aws ecr describe-pull-through-cache-rules --query 'pullThroughCacheRules[].[ecrRepositoryPrefix,upstreamRegistryUrl]'
   ```

## 블록

```hcl
# aws_ecr_repository 리소스 안에: push 시 취약점 스캔 (in-place)
image_scanning_configuration {
  scan_on_push = true
}
```

```hcl
# aws_ecr_repository 리소스 안에: 태그 불변 + 예외 (in-place, provider 6.8.0+)
# "latest 만 덮어쓰기 허용" → IMMUTABLE_WITH_EXCLUSION + latest
# "v1* 만 불변"            → MUTABLE_WITH_EXCLUSION + v1*
image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
image_tag_mutability_exclusion_filter {
  filter      = "latest"
  filter_type = "WILDCARD"
}
```

```hcl
# aws_ecr_repository 리소스 안에: CMK 암호화 (⚠ 생성 시에만 — 기존 리포는 재생성)
encryption_configuration {
  encryption_type = "KMS"
  kms_key         = aws_kms_key.addon.arn
}
```

```hcl
# aws_ecr_repository 리소스 안에: teardown 시 이미지가 있어도 삭제
force_delete = true
```

## 함정

- `encryption_configuration` 은 **⚠ 재생성**(이미지 전부 소실 → 재 push 필요). 기존 리포에 CMK 를 요구하면 재생성 + 이미지 재 push 시간을 배점과 비교한다. `terraform plan` 에 `must be replaced` 가 뜨는지 반드시 본다. 나머지 블록과 lifecycle policy·pull-through 는 in-place/신규.
- `IMMUTABLE` 에서 같은 태그 재 push 는 `ImageTagAlreadyExistsException`. 런북이 `latest` 를 두 번 push 하면 예외 필터에 `latest` 가 있어야 한다. 예외 필터는 최대 5개, `filter_type` 은 `WILDCARD` 만.
- lifecycle policy 는 리포당 1개 — 이미 있으면 이 리소스가 **덮어쓴다**. 평가는 비동기(보통 24시간 이내)라 apply 직후 이미지가 안 지워진다. 채점은 정책 텍스트(`get-lifecycle-policy`)를 본다. 미리보기: `aws ecr start-lifecycle-policy-preview --repository-name <리포>` → `get-lifecycle-policy-preview`.
- `tagStatus = any` 규칙은 rulePriority 가 가장 커야 한다 — 스니펫은 untagged 를 1, any 를 2 로 고정. 규칙을 더 넣으면 any 를 마지막으로 옮긴다. `tagPatternList`(`v*` 와일드카드)는 tagPrefixList 와 배타 — 과제지가 와일드카드를 요구하면 `tagPrefixList` 를 `tagPatternList` 로 바꾼다(확인 필요: 두 키 동시 지정은 거부).
- pull-through cache: Docker Hub(`registry-1.docker.io`)·GHCR 은 Secrets Manager 자격증명 필수라 제외. 노드/Pod 가 `<계정>.dkr.ecr.<리전>.amazonaws.com/<prefix>/<이미지>` 로 pull 하면 첫 pull 때 리포가 자동 생성된다 — pull 주체 Role 에 `ecr:BatchImportUpstreamImage`·`ecr:CreateRepository` 필요(노드 기본 `AmazonEC2ContainerRegistryReadOnly` 에는 없다). prefix 는 계정·리전 내 유일 — set-05 task-1 이 이미 `ecr-public/quay/registry-k8s-io` 를 만든다.
- 레지스트리 레벨 ENHANCED 스캔(`aws_ecr_registry_scanning_configuration`)은 계정당 1개라 스니펫에 넣지 않았다. 과제지가 "Inspector 고급 스캔" 을 요구할 때만 따로 추가(확인 필요: ENHANCED 로 바꾸면 `scan_on_push` 는 무시되고 레지스트리 규칙이 우선).
- `force_delete = true` 가 없으면 이미지가 있는 리포는 destroy 실패.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/ecr.tf`(IMMUTABLE_WITH_EXCLUSION latest·scan·CMK)
- set-03 task-1 `terraform/ecr.tf`(MUTABLE_WITH_EXCLUSION v1*)
- set-05 task-1 `terraform/ecr.tf`(pull-through cache 3종·미러 리포)
- lifecycle policy 실전 구현 없음
