# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

data "aws_caller_identity" "current" {}

# CloudFront 의 origin-facing 관리형 prefix list
# (wsc2026-app-alb 는 CloudFront 에서만 인입 허용 — 요구사항 12)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # 요구사항 9: wsc2026-static-<임의의 영문 4자리>-<본인 비번호>-bucket
  bucket_name = "${var.name_prefix}-static-${var.bucket_suffix}-${var.player_number}-bucket"

  public_subnet_keys  = [for k, v in var.subnets : k if v.tier == "public"]
  private_subnet_keys = [for k, v in var.subnets : k if v.tier == "private"]

  public_subnet_ids  = [for k in local.public_subnet_keys : aws_subnet.this[k].id]
  private_subnet_ids = [for k in local.private_subnet_keys : aws_subnet.this[k].id]

  # 본 클러스터 ARN (Pod Identity trust 한정에 사용)
  cluster_arn = "arn:aws:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"
}