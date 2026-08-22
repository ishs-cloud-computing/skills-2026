# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "addon_vpn_endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.addon.id
}

output "addon_vpn_endpoint_dns" {
  value = aws_ec2_client_vpn_endpoint.addon.dns_name
}

output "addon_vpn_target_private_ip" {
  value = aws_instance.addon_vpn_target.private_ip
}
