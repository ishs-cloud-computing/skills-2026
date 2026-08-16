# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 이 한 줄이 모든 리소스 이름을 바꾼다. 바꾸면 eksctl/cluster.yaml·k8s/00-nodeclass.yaml·
# k8s/20-ingress.yaml·scripts/*.sh 의 클러스터/ALB 이름도 같이 고쳐야 한다.
prefix = "skills"

# 전역 유일해야 한다.
bucket_name = "wsc2026-task3-images-<비번호>"

db_identifier = "apdev-rds-instance"

db_password = "password"
# 존재하는 엔드포인트. WAF 전 룰이 이 경로에서만 동작한다. 밖은 통과 → ALB 404.
# 앱·경로가 바뀌면 여기만 고친다.
# waf_api_path_regexes = ["^/v1/(user|product|stress)(/.*)?$", "^/images/.+$"]

# 스캐너 UA 목록은 여기 없다. 당일 WAF 콘솔에서 regex pattern set을 직접 편집한다 (README STEP 12).
