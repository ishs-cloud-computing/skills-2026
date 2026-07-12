# 엔진 중립 RDS. 당일 다른 엔진(예: PostgreSQL)이 나오면 locals.tf의
# db_engine/db_engine_version/db_port/db_username만 바꿔 apply — DB 스택만 재생성된다.
resource "aws_db_subnet_group" "this" {
  name       = "skills-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "skills-db-subnet"
  }
}

resource "aws_db_instance" "this" {
  identifier     = local.db_identifier
  engine         = local.db_engine
  engine_version = local.db_engine_version
  instance_class = local.db_instance_class
  multi_az       = local.db_multi_az # primary + standby, 채점상 인스턴스 1대

  storage_type      = "gp3"
  allocated_storage = local.db_allocated_storage

  db_name = local.db_name
  port    = local.db_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  username = local.db_username
  password = var.db_password

  skip_final_snapshot = true
  deletion_protection = false
}
