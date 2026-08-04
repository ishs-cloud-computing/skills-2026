# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Secrets Manager (과제지 3-4, 채점 1-2)
# - host 는 Scheme·Port 없는 Cluster Endpoint hostname — aws_docdb_cluster
#   .endpoint 속성이 정확히 그 형태라 그대로 주입 (지급 앱이 형식을 검증함).
# - password 는 random_password: 평문이 코드·저장소에 남지 않게 한다
#   (state 에는 남지만 state 는 로컬 + gitignore).
# - special=false: DocumentDB 금지 문자("/@ 등) 회피 목적 — 영숫자 24자.
# ---------------------------------------------------------------------------

resource "random_password" "docdb" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "docdb" {
  name                    = var.secret_name
  recovery_window_in_days = 0 # teardown 후 즉시 재생성 가능해야 함 (이름 충돌 방지)
}

resource "aws_secretsmanager_secret_version" "docdb" {
  secret_id = aws_secretsmanager_secret.docdb.id
  secret_string = jsonencode({
    username = var.docdb_master_username
    password = random_password.docdb.result
    host     = aws_docdb_cluster.this.endpoint
  })
}
