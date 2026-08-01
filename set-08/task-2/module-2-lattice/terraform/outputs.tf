# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# mark2-2.sh 가 조회하는 값과 동일 형태 — 배포 후 즉시 자가 검증용.

output "client_public_ip" {
  value = aws_instance.client.public_ip
}

output "service_domain" {
  value = aws_vpclattice_service.order.dns_entry[0].domain_name
}

output "service_network_id" {
  value = aws_vpclattice_service_network.this.id
}

output "service_id" {
  value = aws_vpclattice_service.order.id
}

output "target_group_id" {
  value = aws_vpclattice_target_group.order.id
}
