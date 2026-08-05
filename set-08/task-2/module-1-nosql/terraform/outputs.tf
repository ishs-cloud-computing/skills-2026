# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# mark2-1.sh 가 조회하는 값과 동일 형태 — 배포 후 즉시 자가 검증용.

output "client_public_ip" {
  value = aws_instance.client.public_ip
}

output "docdb_endpoint" {
  value = aws_docdb_cluster.this.endpoint
}

output "secret_arn" {
  value = aws_secretsmanager_secret.docdb.arn
}

output "kms_key_arn" {
  value = aws_kms_key.docdb.arn
}
