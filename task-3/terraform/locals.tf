# 과제 상수 모음. 당일 과제 ~30% 변경(이름·CIDR·DB 사양 등)은 이 파일에서 수정한다.
# 앱 목록·이미지 태그와 실행별 입력(비번호·DB 비밀번호)은 variables.tf에 있다.
locals {
  region = "ap-northeast-2"
  azs    = ["ap-northeast-2a", "ap-northeast-2b"]

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.2.0/24", "10.0.3.0/24"]

  cluster_name = "skills-eks"

  # 앱 목록은 variables.tf의 var.apps (기존 local.apps 참조 유지용 별칭)
  apps = var.apps

  # ── DB: 당일 엔진 변경(예: PostgreSQL) 시 engine/engine_version/port/username만 수정.
  # rds.tf·rds-proxy.tf만 이 값을 참조하고 다른 리소스는 DB를 참조하지 않으므로
  # apply 시 DB 스택만 재생성된다 (ALB·CloudFront·EKS는 no-op).
  db_identifier     = "apdev-rds-instance" # 과제지에 명시된 DB identifier
  db_instance_class = "db.t3.micro"
  db_engine         = "mysql" # mysql 또는 postgres (proxy engine_family·인증 타입이 자동 파생됨)
  db_engine_version = "8.0"
  db_name           = "dev" # 논리 데이터베이스 이름 (앱의 MYSQL_DBNAME)
  db_username       = "admin"
  db_port           = 3306 # mysql 3306, postgres 5432
  db_multi_az       = true
  # gp3 스토리지(GB). 이 워크로드는 버퍼풀+PK/인덱스 조회라 baseline 3000 IOPS로 충분.
  db_allocated_storage = 20
}
