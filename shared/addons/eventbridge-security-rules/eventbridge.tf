# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# EventBridge 보안 룰 부착 스니펫 — 룰 패턴 모음 + SNS 직접 / Lambda 핸들러 타깃
# 원본: set-02 task-2 module-3-event(RC 판에서 삭제 — git 이력) eventbridge.tf, set-08 task-2 module-3-event-handling eventbridge.tf·sns.tf
# "AWS API Call via CloudTrail" 패턴은 리전에 management 이벤트를 기록하는 활성 Trail 이 필요
# (cloudtrail-hardening 키트). State-change·GuardDuty·EBS 이벤트는 Trail 불필요.
# ---------------------------------------------------------------------------

locals {
  # key → event pattern. 과제지 룰 이름은 var.addon_evb_rules 에서 key 별로 주입한다.
  addon_evb_patterns = {
    root_login = {
      source      = ["aws.signin"]
      detail-type = ["AWS Console Sign In via CloudTrail"]
      detail      = { userIdentity = { type = ["Root"] } }
    }
    iam_change = {
      source      = ["aws.iam"]
      detail-type = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = ["iam.amazonaws.com"]
        eventName = [
          "CreatePolicy", "CreatePolicyVersion", "DeletePolicy", "DeletePolicyVersion", "SetDefaultPolicyVersion",
          "CreateRole", "DeleteRole", "UpdateAssumeRolePolicy",
          "AttachRolePolicy", "DetachRolePolicy", "PutRolePolicy", "DeleteRolePolicy",
          "AttachUserPolicy", "DetachUserPolicy", "PutUserPolicy", "DeleteUserPolicy",
          "AttachGroupPolicy", "DetachGroupPolicy", "PutGroupPolicy", "DeleteGroupPolicy",
        ]
      }
    }
    sg_ingress = {
      source      = ["aws.ec2"]
      detail-type = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = ["ec2.amazonaws.com"]
        eventName   = ["AuthorizeSecurityGroupIngress"]
      }
    }
    ec2_modify = {
      source      = ["aws.ec2"]
      detail-type = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = ["ec2.amazonaws.com"]
        eventName   = ["ModifyInstanceAttribute"]
      }
    }
    # 네이티브 State-change — 수 초 내 전달, Trail 불필요
    ec2_state = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
      detail      = { state = var.addon_evb_ec2_states }
    }
    ebs_create = {
      source      = ["aws.ec2"]
      detail-type = ["EBS Volume Notification"]
      detail      = { event = ["createVolume"] }
    }
    guardduty = {
      source      = ["aws.guardduty"]
      detail-type = ["GuardDuty Finding"]
      detail      = { severity = [{ numeric = [">=", var.addon_evb_guardduty_min_severity] }] }
    }
  }

  addon_evb_target_arn = var.addon_evb_target_type == "lambda" ? aws_lambda_function.addon_evb_alert[0].arn : aws_sns_topic.addon_evb.arn
}

resource "aws_sns_topic" "addon_evb" {
  name = var.addon_evb_sns_topic_name
  tags = { Name = var.addon_evb_sns_topic_name }
}

resource "aws_sns_topic_subscription" "addon_evb_email" {
  count = var.addon_evb_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.addon_evb.arn
  protocol  = "email"
  endpoint  = var.addon_evb_email
}

# EventBridge → SNS 직접 발행은 토픽 정책이 필요 (IAM role 경로 없음)
data "aws_iam_policy_document" "addon_evb_sns" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.addon_evb.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "addon_evb" {
  arn    = aws_sns_topic.addon_evb.arn
  policy = data.aws_iam_policy_document.addon_evb_sns.json
}

resource "aws_cloudwatch_event_rule" "addon_evb" {
  for_each = var.addon_evb_rules

  name           = each.value
  description    = "addon security rule: ${each.key}"
  event_bus_name = "default"
  event_pattern  = jsonencode(local.addon_evb_patterns[each.key])

  tags = { Name = each.value }
}

resource "aws_cloudwatch_event_rule" "addon_evb_schedule" {
  for_each = var.addon_evb_schedule_rules

  name                = each.key
  description         = "addon schedule rule"
  schedule_expression = each.value

  tags = { Name = each.key }
}

resource "aws_cloudwatch_event_target" "addon_evb" {
  for_each = merge(aws_cloudwatch_event_rule.addon_evb, aws_cloudwatch_event_rule.addon_evb_schedule)

  rule      = each.value.name
  target_id = "addon-${var.addon_evb_target_type}"
  arn       = local.addon_evb_target_arn
}
