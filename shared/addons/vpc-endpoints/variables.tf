# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_vpce_vpc_id" {
  description = "엔드포인트를 만들 기존 VPC ID. 직접 참조하려면 aws_vpc.<기존>.id 로 바꾼다"
  type        = string
}

variable "addon_vpce_vpc_cidr" {
  description = "Interface Endpoint SG 의 443 허용 소스 CIDR (VPC CIDR)"
  type        = string
}

variable "addon_vpce_route_table_ids" {
  description = "Gateway Endpoint 를 연결할 private 라우트 테이블 ID 목록"
  type        = list(string)
  default     = []
}

variable "addon_vpce_subnet_ids" {
  description = "Interface Endpoint ENI 를 둘 private 서브넷 ID 목록 (AZ 당 1개)"
  type        = list(string)
  default     = []
}

variable "addon_vpce_gateway_services" {
  description = "Gateway 타입 서비스 목록 (s3 / dynamodb 만 Gateway 지원)"
  type        = list(string)
  default     = ["s3", "dynamodb"]
}

variable "addon_vpce_interface_services" {
  description = "Interface 타입 서비스 짧은 이름 목록 (ecr.api ecr.dkr logs sts secretsmanager sns sqs monitoring ssm ssmmessages ec2messages kms 등). 빈 목록이면 SG 도 안 만든다"
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs"]
}

variable "addon_vpce_name_prefix" {
  description = "엔드포인트 Name 태그 접두 (<prefix>-<service>)"
  type        = string
  default     = "vpce"
}

variable "addon_vpce_sg_name" {
  description = "Interface Endpoint 용 SG 이름"
  type        = string
  default     = "vpce-sg"
}
