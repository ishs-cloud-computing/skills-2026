# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_db_subnet_group" "this" {
  name       = local.db_subnet_group_name
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = local.db_subnet_group_name
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.db_identifier
  engine         = local.db_engine
  engine_version = local.db_engine_version
  instance_class = local.db_instance_class
  multi_az       = local.db_multi_az

  storage_type       = local.db_storage_type
  allocated_storage  = local.db_allocated_storage
  iops               = local.db_iops
  storage_throughput = local.db_storage_throughput

  db_name = local.db_name
  port    = local.db_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  username = local.db_username
  password = var.db_password

  skip_final_snapshot = true
  deletion_protection = false
}
