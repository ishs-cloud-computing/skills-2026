# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 대회에서 바뀌기 쉬운 값은 여기서 주입한다 (CLAUDE.md 변수 규칙).
# 값은 variables.tf default 와 동일 — 대회 당일 이름/CIDR 변경 시 이 파일만 수정한다.
region        = "ap-northeast-2"
cluster_name  = "skm-eks-cluster"
name_prefix   = "skm"
vpc_cidr      = "10.73.0.0/16"
queue_name    = "skm-order-queue"
ecr_repo_name = "skm-order-processor"

subnets = {
  "skm-subnet-pub-a"  = { cidr = "10.73.0.0/24", az = "ap-northeast-2a", tier = "public" }
  "skm-subnet-pub-c"  = { cidr = "10.73.1.0/24", az = "ap-northeast-2c", tier = "public" }
  "skm-subnet-priv-a" = { cidr = "10.73.10.0/24", az = "ap-northeast-2a", tier = "private" }
  "skm-subnet-priv-c" = { cidr = "10.73.11.0/24", az = "ap-northeast-2c", tier = "private" }
}
