# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# EventBridge Rule (과제지 5-4, 채점 3-4)
# default bus 의 CloudTrail 경유 API Call 중 AuthorizeSecurityGroupIngress 만
# 매칭 → Lambda 타깃. groupId 필터는 넣지 않는다 — 지급 Lambda 가 보호 SG
# 여부를 스스로 판별(IGNORED 처리)하므로 패턴은 과제지 문구 그대로 최소화.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "sg_change" {
  name           = var.rule_name
  event_bus_name = "default"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["AuthorizeSecurityGroupIngress"]
    }
  })

  tags = { Name = var.rule_name }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.sg_change.name
  event_bus_name = "default"
  target_id      = "remediate-lambda"
  arn            = aws_lambda_function.remediate.arn
}

# 채점 3-4 가 lambda get-policy 로 이 리소스 정책의 존재를 확인한다.
resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sg_change.arn
}
