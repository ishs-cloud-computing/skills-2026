# ---------------------------------------------------------------------------
# CloudWatch Logs (요구사항 11)
# - /wsc2026/eks/book-app : Fluent Bit 이 전송하는 앱 액세스 로그.
#   fluent-bit 의 auto_create_group=false 를 위해 선생성한다.
#   (EKS Control Plane 로그 그룹 /aws/eks/... 은 EKS 가 자동 생성)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "book_app" {
  name              = "/${var.name_prefix}/eks/book-app"
  retention_in_days = 7

  tags = { Name = "/${var.name_prefix}/eks/book-app" }
}
