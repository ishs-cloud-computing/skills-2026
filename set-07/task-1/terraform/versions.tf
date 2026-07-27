# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # ECR IMMUTABLE_WITH_EXCLUSION(요구사항 7) 은 provider 6.8.0+ 에서 지원.
      version = "~> 6.51"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# 기본 프로바이더 - 모든 리소스는 서울(ap-northeast-2) 리전에 생성 (유의사항 7)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "unicorn"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront 에 연결되는 WAF(WebACL, scope=CLOUDFRONT), WAF 로그 그룹, 그리고
# Platform KMS 다중 리전 키(MRK)의 프라이머리는 반드시 us-east-1 에 생성한다 (요구사항 4 / 10-3).
provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "unicorn"
      ManagedBy = "terraform"
    }
  }
}
