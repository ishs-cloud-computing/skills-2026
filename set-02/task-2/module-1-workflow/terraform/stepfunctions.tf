# ---------------------------------------------------------------------------
# Step Functions (과제지 4. Step Functions, workflow.md, mark 1-4)
# - wsc2026-student-score-workflow / STANDARD 정확 일치 채점
# - 정의는 statemachine/workflow.asl.json 에 두고 버킷·Lambda ARN 만 주입
# ---------------------------------------------------------------------------

resource "aws_sfn_state_machine" "workflow" {
  name     = var.state_machine_name
  type     = "STANDARD"
  role_arn = aws_iam_role.sfn.arn

  definition = templatefile("${path.module}/statemachine/workflow.asl.json", {
    bucket     = aws_s3_bucket.score.id
    lambda_arn = aws_lambda_function.processor.arn
  })

  depends_on = [aws_iam_role_policy.sfn]

  tags = { Name = var.state_machine_name }
}
