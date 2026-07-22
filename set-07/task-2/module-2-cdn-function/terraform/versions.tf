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

# CDN Function 모듈은 us-east-1 에 생성한다 (과제지 2. CDN Function).
# CloudFront/KVS/Function 은 글로벌 리소스지만 API 는 us-east-1 을 사용한다.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "skillsphone"
      ManagedBy = "terraform"
    }
  }
}
