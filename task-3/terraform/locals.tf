# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

locals {
  region = "ap-northeast-2"
  azs    = ["ap-northeast-2a", "ap-northeast-2b"]

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.2.0/24", "10.0.3.0/24"]

  cluster_name = "skills-eks"
  
  # k8s/20-ingress.yaml의 alb.ingress.kubernetes.io/load-balancer-name과 동일하게 작성한다.
  alb_name = "skills-alb"

  # 앱 목록은 variables.tf의 var.apps를 수정
  apps = toset(var.apps)

  # ── DB: 당일 엔진 변경(예: PostgreSQL) 시 engine/engine_version/port/username만 수정.
  # rds.tf·rds-proxy.tf만 이 값을 참조하고 다른 리소스는 DB를 참조하지 않으므로
  # apply 시 DB 스택만 재생성된다 (ALB·CloudFront·EKS는 no-op).
  # 문서: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
  db_identifier        = "apdev-rds-instance" # 과제지에 명시된 DB identifier
  db_instance_class    = "db.t3.micro"
  db_engine            = "mysql" # mysql 또는 postgres (proxy engine_family·인증 타입이 자동 파생됨)
  db_engine_version    = "8.0"
  db_name              = "dev" # 논리 데이터베이스 이름 (앱의 MYSQL_DBNAME)
  db_username          = "admin"
  db_port              = 3306 # mysql 3306, postgres 5432
  db_multi_az          = true
  db_allocated_storage = 200
}
