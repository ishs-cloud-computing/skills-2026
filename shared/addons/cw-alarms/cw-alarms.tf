# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudWatch Alarm + SNS 부착 스니펫 — set-XX/task-Y/terraform/ 으로 복사해 사용
# 원본: set-08 task-1 cloudwatch.tf (metric filter + alarm), set-08 task-2 module-3 sns.tf
# 기존 리소스(로그 그룹·ALB·RDS 등)는 변수로 받는다 — 세트마다 이름이 다르다.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "addon_alarm" {
  name = var.addon_cwalarm_sns_topic_name
  tags = { Name = var.addon_cwalarm_sns_topic_name }
}

# email 은 수신자가 확인 링크를 눌러야 Confirmed 가 된다 — apply 직후 메일함 확인.
resource "aws_sns_topic_subscription" "addon_alarm_email" {
  count     = var.addon_cwalarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.addon_alarm.arn
  protocol  = "email"
  endpoint  = var.addon_cwalarm_email
}

# ----- 로그 메트릭 필터 + 알람 (set-08 task-1 4xx/5xx 패턴의 범용화) -----
resource "aws_cloudwatch_log_metric_filter" "addon" {
  for_each       = var.addon_cwalarm_log_group_name != "" ? var.addon_cwalarm_log_filters : {}
  name           = each.value.filter_name
  log_group_name = var.addon_cwalarm_log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric_name
    namespace = var.addon_cwalarm_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "addon_log" {
  for_each            = aws_cloudwatch_log_metric_filter.addon
  alarm_name          = var.addon_cwalarm_log_filters[each.key].alarm_name
  metric_name         = each.value.metric_transformation[0].name
  namespace           = var.addon_cwalarm_metric_namespace
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.addon_cwalarm_log_filters[each.key].threshold
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  # 오류 로그가 없는 구간을 INSUFFICIENT_DATA 로 두지 않는다 — 채점은 OK/ALARM 만 본다.
  treat_missing_data = "notBreaching"
  alarm_actions      = [aws_sns_topic.addon_alarm.arn]
  ok_actions         = [aws_sns_topic.addon_alarm.arn]
}

# ----- AWS 네임스페이스 메트릭 알람 -----
resource "aws_cloudwatch_metric_alarm" "addon_metric" {
  for_each            = var.addon_cwalarm_metric_alarms
  alarm_name          = each.value.alarm_name
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.evaluation_periods
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = [aws_sns_topic.addon_alarm.arn]
  ok_actions          = [aws_sns_topic.addon_alarm.arn]
}

# ----- WAF CLOUDFRONT BlockedRequests — 메트릭·알람·토픽 전부 us-east-1 -----
# 알람 액션 SNS 는 알람과 같은 리전이어야 하므로 토픽을 us-east-1 에 따로 둔다.
resource "aws_sns_topic" "addon_alarm_use1" {
  count    = var.addon_cwalarm_waf_cloudfront_name != "" ? 1 : 0
  provider = aws.use1
  name     = "${var.addon_cwalarm_sns_topic_name}-use1"
}

resource "aws_sns_topic_subscription" "addon_alarm_use1_email" {
  count     = var.addon_cwalarm_waf_cloudfront_name != "" && var.addon_cwalarm_email != "" ? 1 : 0
  provider  = aws.use1
  topic_arn = aws_sns_topic.addon_alarm_use1[0].arn
  protocol  = "email"
  endpoint  = var.addon_cwalarm_email
}

resource "aws_cloudwatch_metric_alarm" "addon_waf_cloudfront" {
  count               = var.addon_cwalarm_waf_cloudfront_name != "" ? 1 : 0
  provider            = aws.use1
  alarm_name          = "${var.addon_cwalarm_waf_cloudfront_name}-blocked-alarm"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.addon_cwalarm_waf_blocked_threshold
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  # CLOUDFRONT scope 메트릭 dimension 은 Region=Global 고정
  dimensions = {
    WebACL = var.addon_cwalarm_waf_cloudfront_name
    Region = "Global"
    Rule   = "ALL"
  }
  alarm_actions = [aws_sns_topic.addon_alarm_use1[0].arn]
}
