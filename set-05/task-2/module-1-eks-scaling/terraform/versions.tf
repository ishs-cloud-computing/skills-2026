# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52"
    }
  }
}

# EKS Scaling 모듈은 ap-northeast-2 에 생성한다 (과제지 3. EKS Scaling).
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wsc"
      ManagedBy = "terraform"
    }
  }
}
