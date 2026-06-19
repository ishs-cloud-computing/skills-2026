# ---------------------------------------------------------------------------
# ECR (요구사항 7)
# - Name: wsc-repo
# - KMS 암호화 + Push 시 취약점 스캔 (scan on push)
# - 이미지 태그: v1.0.0 (push 는 Bastion/CI 에서 수행)
#   이미지 경량화(<=8MB), curl 포함은 app/Dockerfile 참고
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "repo" {
  name                 = "wsc-repo"
  image_tag_mutability = "MUTABLE"
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

# ---------------------------------------------------------------------------
# 미러 ECR (Docker Hub 전용 이미지 대응)
# Grafana 공식 이미지는 Docker Hub(docker.io/grafana/grafana) 에만 존재한다.
# public.ecr.aws/quay.io 에 미러가 없고, Docker Hub pull-through 는 인증 자격증명이
# 필요해(대회 규정상 AWS 외 로그인 불가) 사용할 수 없다.
# 따라서 인터넷이 있는 Bastion 에서 익명 pull → 이 repo 로 push 해 미러링한다.
#   docker pull grafana/grafana:<TAG>
#   docker tag  grafana/grafana:<TAG> <ACCOUNT>.dkr.ecr.../wsc-mirror/grafana:<TAG>
#   docker push <ACCOUNT>.dkr.ecr.../wsc-mirror/grafana:<TAG>
# Workload 노드는 이 Private ECR 에서 pull 한다. (grafana-ecr-images.yaml 참고)
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "mirror_grafana" {
  name                 = "wsc-mirror/grafana"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = { Name = "wsc-mirror/grafana" }
}

# ---------------------------------------------------------------------------
# ECR Pull-Through Cache
# Workload Subnet 노드는 인터넷이 없어 퍼블릭 레지스트리에 직접 접근 불가.
# 노드가 Private ECR URL 로 pull 하면 ECR 이 업스트림 레지스트리에서 가져와 캐시.
# 인증 불필요 레지스트리만 사용 (Docker Hub 제외 → 위 미러 repo 로 대응).
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
