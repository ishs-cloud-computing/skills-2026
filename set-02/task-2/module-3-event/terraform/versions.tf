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

# 모듈 3은 eu-west-1 리전 사용 (과제지 3) Cloud Event Handling 개요)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wsc2026"
      ManagedBy = "terraform"
    }
  }
}
