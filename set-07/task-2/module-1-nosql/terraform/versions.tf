# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52"
    }
    # 제공 lambda.py 를 zip 으로 패키징 (lambda.tf archive_file)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# NoSQL 모듈은 ap-southeast-1 에 생성한다 (과제지 1. NoSQL).
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "bigbae"
      ManagedBy = "terraform"
    }
  }
}
