# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "healthcheck_url" {
  value = "http://${aws_instance.app.public_ip}:8080/healthcheck"
}
