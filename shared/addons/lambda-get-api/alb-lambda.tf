# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# (a) ALB → Lambda 노출. 기존 리스너에 GET+경로(+origin-verify 헤더) 규칙을 추가한다.
# 원본: set-05 task-1 alb.tf (GET /v1/book → Lambda, POST → Pod), set-07 task-1 alb.tf.
# alb_listener_arn 이 비어 있으면 이 파일의 리소스는 전부 생성되지 않는다.
# ---------------------------------------------------------------------------

locals {
  addon_lamget_alb = var.addon_lamget_alb_listener_arn != "" ? 1 : 0
}

resource "aws_lb_target_group" "addon_lamget" {
  count = local.addon_lamget_alb

  name        = "${substr(var.addon_lamget_function_name, 0, 29)}-tg"
  target_type = "lambda"

  tags = { Name = "${var.addon_lamget_function_name}-tg" }
}

resource "aws_lambda_permission" "addon_lamget_alb" {
  count = local.addon_lamget_alb

  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.addon_lamget.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.addon_lamget[0].arn
}

resource "aws_lb_target_group_attachment" "addon_lamget" {
  count = local.addon_lamget_alb

  target_group_arn = aws_lb_target_group.addon_lamget[0].arn
  target_id        = aws_lambda_function.addon_lamget.arn
  depends_on       = [aws_lambda_permission.addon_lamget_alb]
}

resource "aws_lb_listener_rule" "addon_lamget" {
  count = local.addon_lamget_alb

  listener_arn = var.addon_lamget_alb_listener_arn
  priority     = var.addon_lamget_alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.addon_lamget[0].arn
  }

  condition {
    path_pattern {
      values = [var.addon_lamget_alb_path]
    }
  }
  condition {
    http_request_method {
      values = ["GET"]
    }
  }
  # 기존 규칙이 CloudFront origin-verify 헤더를 검사하면 이 규칙도 같은 조건을 달아야 우회 경로가 안 생긴다
  dynamic "condition" {
    for_each = var.addon_lamget_alb_header_name != "" ? [1] : []
    content {
      http_header {
        http_header_name = var.addon_lamget_alb_header_name
        values           = [var.addon_lamget_alb_header_value]
      }
    }
  }
}
