# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # Lambda Runtime python3.14 를 인식하는 provider 필요 (aws 6.x)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# REST API 모듈은 us-east-1 에 생성한다 (과제지 6. REST API Implement).
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wsc"
      ManagedBy = "terraform"
    }
  }
}
