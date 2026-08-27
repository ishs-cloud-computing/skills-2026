# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.53.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }
}

provider "aws" {
  region = var.region
}
