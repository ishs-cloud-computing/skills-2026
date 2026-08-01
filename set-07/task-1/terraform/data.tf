# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# CloudFront 의 origin-facing 관리형 prefix list (unicorn-alb 는 CloudFront 에서만 인입 허용)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "unicorn-web-${data.aws_caller_identity.current.account_id}"

  public_subnet_keys  = [for k, v in var.subnets : k if v.tier == "public"]
  private_subnet_keys = [for k, v in var.subnets : k if v.tier == "private"]

  public_subnet_ids  = [for k in local.public_subnet_keys : aws_subnet.this[k].id]
  private_subnet_ids = [for k in local.private_subnet_keys : aws_subnet.this[k].id]

  # 본 클러스터 ARN (Pod Identity trust / audit role 권한 범위 한정에 사용)
  cluster_arn = "arn:aws:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"

  audit_external_id = "${var.audit_external_id_prefix}${var.player_number}"

  grafana_admin_user     = var.grafana_admin_user != "" ? var.grafana_admin_user : "skills${var.player_number}"
  grafana_admin_password = var.grafana_admin_password != "" ? var.grafana_admin_password : "HelloKrSkills!${var.player_number}@"
}
