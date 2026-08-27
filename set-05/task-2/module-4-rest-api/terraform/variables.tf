# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "region" {
  description = "REST API 모듈 리전"
  type        = string
  default     = "us-east-1"
}

variable "table_name" {
  type    = string
  default = "wsc-rest-table"
}

variable "lambda_name" {
  type    = string
  default = "wsc-rest-function"
}

variable "api_name" {
  type    = string
  default = "wsc-rest-api"
}

variable "stage_name" {
  type    = string
  default = "prod"
}

variable "api_key_name" {
  type    = string
  default = "wsc-rest-api-key"
}
