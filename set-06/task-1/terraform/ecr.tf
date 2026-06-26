# ---------------------------------------------------------------------------
# ECR (요구사항 5)
# - Repository Name: book (채점 2-1)
# - KMS 암호화 + Push 시 스캔
# - book 이미지 크기 <= 3MB (채점 2-2). app/Dockerfile(FROM scratch) + zstd 압축.
# - 클러스터 운영에 필요한 외부 이미지는 Private ECR(pull-through)로 제공.
#   채점은 public.ecr.aws 레지스트리 이미지를 ecr-public pull-through 로 확인(채점 4-5).
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "book" {
  name                 = "book"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = { Name = "book" }
}

# Grafana 공식 이미지는 Docker Hub 전용이라 ecr-public/quay 미러가 없고,
# Docker Hub pull-through 는 인증이 필요(대회 규정상 불가)하다. 인터넷이 있는
# 운영 머신에서 익명 pull → 이 repo 로 push 해 미러링한다. 노드는 여기서 pull.
resource "aws_ecr_repository" "mirror_grafana" {
  name                 = "gj2026-mirror/grafana"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = { Name = "gj2026-mirror/grafana" }
}

# Bottlerocket bootstrap container 이미지 (노드명 커스텀용, eksctl bottlerocket.settings
# .bootstrap-containers 의 source 로 참조). 부팅 시 IMDS 로 instance-id 를 읽어
# kubernetes.hostname-override=gj2026.<id>.<role>.node 로 설정한다(채점 4-3).
resource "aws_ecr_repository" "bootstrap" {
  name                 = "gj2026-bootstrap"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = { Name = "gj2026-bootstrap" }
}

# ECR Pull-Through Cache: 노드는 인터넷이 없어 퍼블릭 레지스트리에 직접 접근 불가.
# Private ECR URL(.../ecr-public/...) 로 pull 하면 ECR 이 public.ecr.aws 에서 받아 캐시.
resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}
