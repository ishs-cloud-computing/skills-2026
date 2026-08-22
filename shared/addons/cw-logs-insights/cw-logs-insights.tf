# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudWatch Logs Insights 저장 쿼리 부착 스니펫 — set-XX/task-Y/terraform/ 으로 복사해 사용
# 원본: task-3 NOTES.md "Logs Insights 쿼리 세트"(WAF, 라이브 검증), set-08 task-1 앱 로그 형식
#       ("... access method=GET path=/nope status=404 duration=...").
# 쿼리 정의는 리전 리소스다 — WAF(CLOUDFRONT) 로그 그룹은 us-east-1 이라 aws.use1 로 만든다.
# 쿼리 원문은 README "블록" 절과 동일 — 콘솔에 직접 붙여 넣을 때는 그쪽을 쓴다.
# ---------------------------------------------------------------------------

locals {
  # 앱 로그: status/path/duration 은 regex parse — 로그 앞뒤 형식(JSON 래핑 등)에 영향받지 않는다.
  addon_cwli_app_queries = {
    "status-count"    = <<-EOT
      parse @message /status=(?<status>[0-9]{3})/
      | filter ispresent(status)
      | stats count() as cnt by status
      | sort status asc
    EOT
    "error-paths"     = <<-EOT
      parse @message /path=(?<path>[^ ]+) status=(?<status>[0-9]{3})/
      | filter status like /^[45]/
      | stats count() as cnt by status, path
      | sort cnt desc
      | limit 20
    EOT
    "latency-by-path" = <<-EOT
      parse @message /path=(?<path>[^ ]+) status=(?<status>[0-9]{3}) duration=(?<duration>[0-9.]+)/
      | filter ispresent(duration)
      | stats count() as cnt, avg(duration) as avg_ms, pct(duration, 95) as p95_ms, max(duration) as max_ms by path
      | sort p95_ms desc
    EOT
    "error-trend-5m"  = <<-EOT
      parse @message /status=(?<status>[0-9]{3})/
      | filter status like /^5/
      | stats count() as errors by bin(5m) as t
      | sort t asc
    EOT
    "error-keywords"  = <<-EOT
      filter @message like /(?i)(error|exception|panic|fatal|timeout)/
      | fields @timestamp, @logStream, @message
      | sort @timestamp desc
      | limit 100
    EOT
  }

  # WAF 로그: UA 는 httpRequest.headers[] 안이라 필드 접근 불가 — parse 로 추출 (task-3 검증).
  # 집계 대상 필드는 전 레코드 존재 확인됨: action, terminatingRuleId, httpRequest.{uri,clientIp,country}
  addon_cwli_waf_queries = {
    "action-trend-5m" = <<-EOT
      stats count() as cnt by bin(5m) as t, action
      | sort t asc
    EOT
    "block-by-rule"   = <<-EOT
      filter action = "BLOCK"
      | stats count() as cnt by terminatingRuleId
      | sort cnt desc
    EOT
    "block-by-ua"     = <<-EOT
      filter action = "BLOCK"
      | parse @message '"name":"User-Agent","value":"*"' as ua
      | stats count() as cnt by ua
      | sort cnt desc
      | limit 20
    EOT
    "block-by-path"   = <<-EOT
      filter action = "BLOCK"
      | stats count() as cnt by httpRequest.uri
      | sort cnt desc
      | limit 20
    EOT
    "block-by-ip"     = <<-EOT
      filter action = "BLOCK"
      | stats count() as cnt by httpRequest.clientIp, httpRequest.country
      | sort cnt desc
      | limit 20
    EOT
    "count-rules"     = <<-EOT
      filter ispresent(nonTerminatingMatchingRules.0.ruleId)
      | stats count() as cnt by nonTerminatingMatchingRules.0.ruleId, action
      | sort cnt desc
    EOT
  }
}

resource "aws_cloudwatch_query_definition" "addon_app" {
  for_each        = length(var.addon_cwli_app_log_group_names) > 0 ? local.addon_cwli_app_queries : {}
  name            = "${var.addon_cwli_name_prefix}/app/${each.key}"
  log_group_names = var.addon_cwli_app_log_group_names
  query_string    = each.value
}

# REGIONAL scope WAF(로그 그룹이 기본 리전)면 아래 provider 줄을 지운다.
resource "aws_cloudwatch_query_definition" "addon_waf" {
  for_each        = length(var.addon_cwli_waf_log_group_names) > 0 ? local.addon_cwli_waf_queries : {}
  provider        = aws.use1
  name            = "${var.addon_cwli_name_prefix}/waf/${each.key}"
  log_group_names = var.addon_cwli_waf_log_group_names
  query_string    = each.value
}
