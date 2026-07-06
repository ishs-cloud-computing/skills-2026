# RDS Proxy: 스파이크로 API 파드가 늘어도 커넥션을 풀링/멀티플렉싱해
# RDS max_connections 고갈을 막는다. JSON 응답이 요청 uuid를 echo해 CloudFront
# 캐시가 불가 → 모든 읽기가 DB로 내려오므로 프록시가 병목 방어의 핵심이다.

# RDS와 프록시가 공유하는 SG. VPC 내부(파드→프록시→DB)만 DB 포트 허용.
resource "aws_security_group" "db" {
  name        = "skills-db"
  description = "RDS and RDS Proxy, DB port from VPC only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "DB port from within VPC"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "skills-db" }
}

# 프록시 인증 자격증명 (Secrets Manager 필수)
resource "aws_secretsmanager_secret" "db" {
  name = "skills-db-credentials"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = aws_db_instance.this.username
    password = var.db_password
  })
}

data "aws_iam_policy_document" "proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "skills-db-proxy"
  assume_role_policy = data.aws_iam_policy_document.proxy_assume.json
}

data "aws_iam_policy_document" "proxy_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_role_policy" "proxy_secret" {
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy_secret.json
}

resource "aws_db_proxy" "this" {
  name          = "skills-db-proxy"
  engine_family = contains(["mysql", "mariadb"], var.db_engine) ? "MYSQL" : "POSTGRESQL"
  role_arn      = aws_iam_role.proxy.arn

  vpc_subnet_ids         = aws_subnet.private[*].id
  vpc_security_group_ids = [aws_security_group.db.id]
  # 앱(수정 불가)이 TLS를 협상 안 할 수 있으므로 강제하지 않는다.
  require_tls = false

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db.arn
    # 앱(수정 불가)이 non-TLS로 접속하는데 MySQL 8.0 기본 caching_sha2_password는
    # 평문 연결에서 인증이 실패한다 → 프록시 클라이언트 인증을 MySQL Native로 고정.
    client_password_auth_type = contains(["mysql", "mariadb"], var.db_engine) ? "MYSQL_NATIVE_PASSWORD" : "POSTGRES_SCRAM_SHA_256"
  }
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = aws_db_instance.this.identifier
}
