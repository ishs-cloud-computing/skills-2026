terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # Lambda Runtime python3.14 를 인식하는 최신 provider 필요 (5.60 enum 에는 없음)
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80"
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
