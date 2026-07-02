# Task Definition이 이 리소스를 참조하므로 첫 태스크 기동 전에 항상 존재
resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = 7

  tags = {
    Name = local.log_group_name
  }
}

# 앱 access 로그 실측: "... access method=GET path=/nope status=404 duration=..."
# standalone 정규식 패턴 사용 — space-delimited 후미 ellipsis는 공식 문서에 예시가 없어 회피.
# "DynamoDB put error: ... StatusCode: 400" 라인은 대소문자 불일치로 매칭되지 않음.
resource "aws_cloudwatch_log_metric_filter" "http_4xx" {
  name           = local.filter_4xx_name
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "%status=4[0-9][0-9]%"

  metric_transformation {
    name      = local.metric_4xx_name
    namespace = var.metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  name           = local.filter_5xx_name
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "%status=5[0-9][0-9]%"

  metric_transformation {
    name      = local.metric_5xx_name
    namespace = var.metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "http_4xx" {
  alarm_name          = local.alarm_4xx_name
  metric_name         = local.metric_4xx_name
  namespace           = var.metric_namespace
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = local.alarm_5xx_name
  metric_name         = local.metric_5xx_name
  namespace           = var.metric_namespace
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
}
