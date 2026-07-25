# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  public_subnet_keys  = [for k, v in var.subnets : k if v.tier == "public"]
  private_subnet_keys = [for k, v in var.subnets : k if v.tier == "private"]

  # NAT GW 는 같은 AZ 의 public 서브넷에 놓아야 private 라우트가 AZ 를 넘지 않는다.
  public_by_az = { for k in local.public_subnet_keys : var.subnets[k].az => k }
}
