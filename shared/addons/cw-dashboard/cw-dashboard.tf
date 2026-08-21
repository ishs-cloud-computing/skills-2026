# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# CloudWatch Dashboard 부착 스니펫 — cw-dashboard.tf + dashboard.json.tftpl + variables.tf 를
# set-XX/task-Y/terraform/ 으로 복사해 사용. dimension 변수가 비어 있지 않은 위젯만 들어간다.
# 콘솔에서 만든 대시보드는 재현이 안 된다 — JSON 템플릿을 소스로 둔다.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "addon" {
  dashboard_name = var.addon_cwdash_name
  dashboard_body = templatefile("${path.module}/dashboard.json.tftpl", {
    name                 = var.addon_cwdash_name
    region               = var.addon_cwdash_region
    period               = var.addon_cwdash_period
    alb_arn_suffix       = var.addon_cwdash_alb_arn_suffix
    rds_instance_id      = var.addon_cwdash_rds_instance_id
    ecs_cluster_name     = var.addon_cwdash_ecs_cluster_name
    ecs_service_name     = var.addon_cwdash_ecs_service_name
    eks_cluster_name     = var.addon_cwdash_eks_cluster_name
    lambda_function_name = var.addon_cwdash_lambda_function_name
    waf_acl_name         = var.addon_cwdash_waf_acl_name
    waf_metric_region    = var.addon_cwdash_waf_metric_region
    waf_dimension_region = var.addon_cwdash_waf_dimension_region
  })
}
