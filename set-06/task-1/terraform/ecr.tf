# ---------------------------------------------------------------------------
# ECR (plan.md §3.3)
# - book: 채점 2-1/2-2 대상. latest 태그 zstd push 는 런북에서 수행
# - pull-through cache rule(ecr-public): 채점 4-5 가
#   <acct>.dkr.ecr.<region>.amazonaws.com/ecr-public/nginx/nginx:latest 를 pull
# - 핵심 워크로드 이미지(bootstrap/grafana/LBC)는 PTC 에 의존하지 않고 직접 push
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "book" {
  name         = "book"
  force_delete = true
}

resource "aws_ecr_pull_through_cache_rule" "public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

# 직접 push 용 리포지토리 — 노드 부팅·핵심 경로는 PTC 미사용 (plan.md §3.3)
resource "aws_ecr_repository" "direct" {
  for_each = toset([
    "${var.name_prefix}/br-bootstrap", # Bottlerocket bootstrap container
    "mirror/grafana",                  # Docker Hub 전용이라 PTC 불가
    "mirror/aws-load-balancer-controller",
  ])

  name         = each.value
  force_delete = true
}
