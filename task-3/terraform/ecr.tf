# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_ecr_repository" "app" {
  for_each = local.apps

  name         = each.key
  force_delete = true
}
