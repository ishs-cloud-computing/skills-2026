# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "addon_rds_endpoint" {
  value = aws_db_instance.addon.address
}

output "addon_rds_proxy_endpoint" {
  value = var.addon_rds_proxy_enabled ? aws_db_proxy.addon[0].endpoint : null
}

output "addon_rds_client_instance_id" {
  value = aws_instance.addon_rds_client.id
}
