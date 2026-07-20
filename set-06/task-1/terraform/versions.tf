# ---------------------------------------------------------------------------
# Provider 버전 고정 (Work Rule #2)
# - aws_cloudfront_vpc_origin(5.77+), aws_dynamodb_resource_policy(5.43+) 필요
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# 기본 프로바이더 — WAF 를 제외한 전 리소스는 서울 리전
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    }
  }
}

# CLOUDFRONT scope Web ACL 은 AWS API 제약상 us-east-1 에서만 생성 가능 (plan.md §3.10)
provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  ecr_url    = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}
