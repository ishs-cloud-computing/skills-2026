# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 대회에서 바뀌기 쉬운 값은 여기서 주입한다 (CLAUDE.md 변수 규칙).
# 값은 variables.tf default 와 동일 — 대회 당일 이름/CIDR/리전 변경 시 이 파일만 수정한다.
region             = "ap-southeast-1"
availability_zone  = "ap-southeast-1a"
name_prefix        = "bigbae-nosql"
vpc_cidr           = "10.71.0.0/16"
public_subnet_cidr = "10.71.0.0/24"

reservation_table_name = "bigbae-nosql-reservation-table"
gsi_name               = "gsi-user-reservations"
audit_table_name       = "bigbae-nosql-audit-table"
lambda_name            = "bigbae-nosql-reservation-audit"
ec2_name               = "bigbae-nosql-app-ec2"
instance_type          = "t3.small"
app_port               = 8080
