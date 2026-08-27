# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${var.bucket_name_prefix}-${var.player_number}"

  public_subnet_keys  = [for k, v in var.subnets : k if v.tier == "public"]
  private_subnet_keys = [for k, v in var.subnets : k if v.tier == "private"]

  public_subnet_ids  = [for k in local.public_subnet_keys : aws_subnet.this[k].id]
  private_subnet_ids = [for k in local.private_subnet_keys : aws_subnet.this[k].id]

  # 제공자료 위치 (수정 금지, 그대로 사용 — 유의사항 8)
  provided_dir = "${path.module}/../../../shared/provided/task-1"
}
