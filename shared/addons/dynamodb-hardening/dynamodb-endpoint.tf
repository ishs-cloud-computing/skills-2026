# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DynamoDB Gateway 엔드포인트 부착 스니펫
# 원본: set-08 task-1 vpc.tf (채점이 Gateway 타입 + com.amazonaws.<region>.dynamodb 서비스명 검사)
# ---------------------------------------------------------------------------

data "aws_region" "addon_ddb" {}

resource "aws_vpc_endpoint" "addon_ddb" {
  vpc_id            = var.addon_ddb_vpc_id
  service_name      = "com.amazonaws.${data.aws_region.addon_ddb.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.addon_ddb_route_table_ids

  tags = { Name = var.addon_ddb_endpoint_name }
}
