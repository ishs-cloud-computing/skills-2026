# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Karpenter interruption 처리 — SQS 큐 + EventBridge 룰 4종 + 컨트롤러 정책
# 공식 karpenter cloudformation.yaml 의 KarpenterInterruptionQueue 부분을 Terraform 으로 옮겼다.
# helm: --set settings.interruptionQueue=<큐 이름>
# ---------------------------------------------------------------------------

locals {
  addon_ekscale_queue_name = coalesce(var.addon_ekscale_queue_name, var.addon_ekscale_cluster_name)

  # 룰 4종: Health 예정 이벤트 / Spot 중단 경고 / Rebalance 권고 / 인스턴스 상태 변경
  addon_ekscale_event_rules = {
    scheduled-change = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
    }
    spot-interruption = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance-state-change = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
  }
}

resource "aws_sqs_queue" "addon_karpenter_interruption" {
  name                      = local.addon_ekscale_queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = { Name = local.addon_ekscale_queue_name }
}

data "aws_iam_policy_document" "addon_karpenter_interruption_queue" {
  statement {
    sid       = "EC2InterruptionPolicy"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.addon_karpenter_interruption.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.addon_karpenter_interruption.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "addon_karpenter_interruption" {
  queue_url = aws_sqs_queue.addon_karpenter_interruption.id
  policy    = data.aws_iam_policy_document.addon_karpenter_interruption_queue.json
}

resource "aws_cloudwatch_event_rule" "addon_karpenter_interruption" {
  for_each      = local.addon_ekscale_event_rules
  name          = "${local.addon_ekscale_queue_name}-${each.key}"
  event_pattern = jsonencode(each.value)
}

resource "aws_cloudwatch_event_target" "addon_karpenter_interruption" {
  for_each = aws_cloudwatch_event_rule.addon_karpenter_interruption
  rule     = each.value.name
  arn      = aws_sqs_queue.addon_karpenter_interruption.arn
}

# 컨트롤러가 큐를 읽도록 — 기존 Karpenter 컨트롤러 정책에 이 문장을 합쳐도 된다
resource "aws_iam_policy" "addon_karpenter_interruption" {
  name = "${local.addon_ekscale_queue_name}-karpenter-interruption-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.addon_karpenter_interruption.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "addon_karpenter_interruption" {
  count      = var.addon_ekscale_karpenter_role_name != "" ? 1 : 0
  role       = var.addon_ekscale_karpenter_role_name
  policy_arn = aws_iam_policy.addon_karpenter_interruption.arn
}

output "addon_ekscale_interruption_queue_name" {
  value = aws_sqs_queue.addon_karpenter_interruption.name
}
