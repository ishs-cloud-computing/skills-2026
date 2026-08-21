# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# DocumentDB 하드닝 부착 스니펫 — 클러스터 파라미터 그룹 + 읽기 인스턴스
# 원본: set-08 task-2 module-1-nosql docdb.tf (기본 파라미터 그룹·인스턴스 1개).
# 클러스터 안 인자(로그 내보내기·삭제 방지·백업 윈도우)는 ./README.md 블록.
# ---------------------------------------------------------------------------

# tls 는 static 파라미터 — 값이 바뀌면 인스턴스 재부팅 전까지 반영되지 않는다.
# audit_logs/profiler 는 클러스터의 enabled_cloudwatch_logs_exports 와 **둘 다** 켜야 로그가 나간다.
resource "aws_docdb_cluster_parameter_group" "addon" {
  name   = var.addon_docdb_parameter_group_name
  family = var.addon_docdb_family

  parameter {
    name  = "tls"
    value = var.addon_docdb_tls ? "enabled" : "disabled"
  }

  parameter {
    name  = "audit_logs"
    value = var.addon_docdb_audit_logs ? "enabled" : "disabled"
  }

  parameter {
    name  = "profiler"
    value = var.addon_docdb_profiler ? "enabled" : "disabled"
  }

  parameter {
    name  = "profiler_threshold_ms"
    value = tostring(var.addon_docdb_profiler_threshold_ms)
  }
}

# 읽기 인스턴스. 같은 클러스터의 인스턴스는 전부 reader 후보이며 promotion_tier 가 낮을수록 먼저 승격된다.
resource "aws_docdb_cluster_instance" "addon_reader" {
  count = var.addon_docdb_reader_count

  identifier         = "${var.addon_docdb_reader_identifier_prefix}-${count.index + 1}"
  cluster_identifier = var.addon_docdb_cluster_identifier
  instance_class     = var.addon_docdb_reader_instance_class
  promotion_tier     = 1
}
