# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

locals {
  vpc_name            = "${var.prefix}-vpc"
  igw_name            = "${var.prefix}-igw"
  nat_name            = "${var.prefix}-nat"
  s3_endpoint_name    = "${var.prefix}-s3-vpce"
  public_rtb_name     = "${var.prefix}-public-rtb"
  private_rtb_name    = "${var.prefix}-private-rtb"
  public_subnet_name  = "${var.prefix}-public"
  private_subnet_name = "${var.prefix}-private"

  cluster_name = "${var.prefix}-eks"
  alb_name     = "${var.prefix}-alb"

  waf_name             = "${var.prefix}-waf"
  waf_log_group        = "aws-waf-logs-${local.waf_name}"
  waf_api_paths_name   = "${var.prefix}-waf-api-paths"
  waf_scanner_uas_name = "${var.prefix}-waf-scanner-uas"


  cdn_name          = "${var.prefix}-cdn"
  cdn_function_name = "${var.prefix}-strip-images"
  cdn_oac_name      = "${var.prefix}-s3-oac"

  cloudshell_sg_name = "${var.prefix}-cloudshell-sg"

  db_sg_name           = "${var.prefix}-db-sg"
  db_subnet_group_name = "${var.prefix}-db-subnet-group"
  db_secret_name       = "${var.prefix}-db-credentials"
  db_proxy_name        = "${var.prefix}-db-proxy"
  db_proxy_role_name   = "${var.prefix}-db-proxy-role"

  region = "ap-northeast-2"
  azs    = ["ap-northeast-2a", "ap-northeast-2b"]

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.2.0/24", "10.0.3.0/24"]

  apps = toset(var.apps)

  db_instance_class     = "db.t3.micro"
  db_engine             = "mysql"
  db_engine_version     = "8.0"
  db_name               = "dev"
  db_username           = "admin"
  db_port               = 3306
  db_multi_az           = true
  db_storage_type       = "gp3"
  db_allocated_storage  = 400
  db_iops               = 12000
  db_storage_throughput = 500
}
