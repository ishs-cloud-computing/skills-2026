# ---------------------------------------------------------------------------
# ECR (요구사항 7)
# - Name: wsc-repo
# - KMS 암호화 + Push 시 취약점 스캔 (scan on push)
# - 이미지 태그: v1.0.0 (push 는 Bastion/CI 에서 수행)
#   이미지 경량화(<=8MB), curl 포함은 app/Dockerfile 참고
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "repo" {
  name                 = "wsc-repo"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = { Name = "wsc-repo" }
}

# Enhanced scanning(취약점 상세 분석) 활성화
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "wsc-repo"
      filter_type = "WILDCARD"
    }
  }
}

# ---------------------------------------------------------------------------
# ECR Pull-Through Cache
# Workload Subnet 노드는 인터넷이 없어 퍼블릭 레지스트리에 직접 접근 불가.
# 노드가 Private ECR URL 로 pull 하면 ECR 이 업스트림 레지스트리에서 가져와 캐시.
# 인증 불필요 레지스트리만 사용 (Docker Hub 제외).
# ---------------------------------------------------------------------------
resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

resource "aws_ecr_pull_through_cache_rule" "quay" {
  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}

resource "aws_ecr_pull_through_cache_rule" "k8s" {
  ecr_repository_prefix = "registry-k8s-io"
  upstream_registry_url = "registry.k8s.io"
}
