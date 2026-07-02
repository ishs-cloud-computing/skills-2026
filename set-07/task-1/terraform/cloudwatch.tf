# ---------------------------------------------------------------------------
# CloudWatch Log Groups (요구사항 8 / 12) — Platform CMK 암호화
# - /unicorn/eks/book-app                : Fluent Bit 가 Book App 로그 전송 (auto_create_group=false)
# - /aws/eks/<cluster>/cluster           : EKS Control Plane 로그. eksctl 생성 전 선생성해 CMK 적용.
# (VPC flow log / WAF / Lambda 로그 그룹은 각 도메인 파일에서 생성)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "book_app" {
  name              = "/unicorn/eks/book-app"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform.arn

  tags = { Name = "unicorn-book-app-log" }
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform.arn

  tags = { Name = "unicorn-eks-cluster-log" }
}
