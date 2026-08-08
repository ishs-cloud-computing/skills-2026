# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# S3 버킷 이름 (전역 유일). 이미 존재하는 이름이면 apply가 즉시 실패하므로
# 그때는 이 한 줄만 바꾼다.
bucket_name = "wsc2026-task3-images"

# RDS master 비밀번호. 저장소 전체에서 이 값을 적는 곳은 여기 한 줄뿐이고,
# 앱 매니페스트 치환값은 terraform output db_password 로 흘러간다.
db_password = "REDACTED"
