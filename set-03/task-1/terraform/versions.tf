terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # ECR MUTABLE_WITH_EXCLUSION(요구사항 6) 은 provider 6.8.0+ 에서 지원.
      version = "~> 6.51"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# 기본 프로바이더 - 모든 리소스는 서울(ap-northeast-2) 리전에 생성 (유의사항 9)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wsc2026"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront 에 연결되는 WAF(WebACL) 는 scope=CLOUDFRONT 라 us-east-1 에 생성해야 한다 (요구사항 13)
provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "wsc2026"
      ManagedBy = "terraform"
    }
  }
}
