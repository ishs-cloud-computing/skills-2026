terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.54"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

# 모듈 2는 ap-northeast-2 리전 사용 (과제지 2) Real-time data analytics 개요)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wsc2026"
      ManagedBy = "terraform"
    }
  }
}
