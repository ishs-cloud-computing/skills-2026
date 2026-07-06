# 엔진 중립 RDS. 당일 다른 엔진(예: PostgreSQL)이 나오면 variables.tf의
# db_engine/db_engine_version/db_port/db_username만 바꿔 apply — DB 스택만 재생성된다.
resource "aws_db_subnet_group" "this" {
  name       = "skills-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "skills-db-subnet"
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.db_identifier
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  multi_az       = var.db_multi_az # primary + standby, 채점상 인스턴스 1대

  storage_type      = "gp3"
  allocated_storage = var.db_allocated_storage

  db_name = var.db_name
  port    = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  username = var.db_username
  password = var.db_password

  skip_final_snapshot = true
  deletion_protection = false
}
