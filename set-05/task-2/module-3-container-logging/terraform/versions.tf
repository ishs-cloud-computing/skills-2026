# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Container Logging 모듈은 ap-northeast-1 에 생성한다 (과제지 5. Container Logging).
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wsc"
      ManagedBy = "terraform"
    }
  }
}
