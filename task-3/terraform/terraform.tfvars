# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 이 한 줄이 모든 리소스 이름을 바꾼다. 바꾸면 eksctl/cluster.yaml·k8s/00-nodeclass.yaml·
# k8s/20-ingress.yaml·scripts/*.sh 의 클러스터/ALB 이름도 같이 고쳐야 한다.
prefix = "skills"

# 전역 유일해야 한다.
bucket_name = "wsc2026-task3-images-103"

db_identifier = "apdev-rds-instance"

db_password = "password"
