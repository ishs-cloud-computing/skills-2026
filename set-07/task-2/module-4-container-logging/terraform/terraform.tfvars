# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 대회에서 바뀌기 쉬운 값은 여기서 주입한다 (CLAUDE.md 변수 규칙).
# 값은 variables.tf default 와 동일 — 대회 당일 이름/CIDR 변경 시 이 파일만 수정한다.
region                = "ap-northeast-1"
cluster_name          = "o11y-cluster"
vpc_cidr              = "10.74.0.0/16"
app_alb_name          = "o11y-app-alb"
app_tg_name           = "o11y-app-tg"
grafana_alb_name      = "o11y-grafana-alb"
grafana_tg_name       = "o11y-grafana-tg"
ecr_repo_name         = "o11y-log-generator"
bastion_instance_type = "t3.medium"
ssh_password          = "Skill53##"

subnets = {
  "o11y-subnet-pub-a"  = { cidr = "10.74.0.0/24", az = "ap-northeast-1a", tier = "public" }
  "o11y-subnet-pub-c"  = { cidr = "10.74.1.0/24", az = "ap-northeast-1c", tier = "public" }
  "o11y-subnet-priv-a" = { cidr = "10.74.10.0/24", az = "ap-northeast-1a", tier = "private" }
  "o11y-subnet-priv-c" = { cidr = "10.74.11.0/24", az = "ap-northeast-1c", tier = "private" }
}
