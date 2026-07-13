terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.54"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# 모든 리소스는 서울(ap-northeast-2) 리전에 생성 (유의사항 7)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wskorea26"
      ManagedBy = "terraform"
    }
  }
}
