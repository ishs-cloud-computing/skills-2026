# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Book App Image (요구사항 7)
# - 제공된 Go binary "book" (x86, TCP/8080) 배포
# - alpine 기반: ECR Basic scanning(Clair)이 OS 패키지 DB 를 읽어 스캔 COMPLETE 됨.
#   최신 패치 alpine 으로 공개 취약점 0 유지 (요구사항 7: 취약점 존재 금지).
# - 태그 v1.0.0, latest 두 개로 push (요구사항 7).
#
# 빌드/푸시는 일반 CloudShell 에서 한다 (대회 PC 는 Docker·WSL 사용 불가 — README step 2).
# 빌드 컨텍스트에 이 파일과 book 두 개만 있으면 된다.
#   docker build -t "$ECR:v1.0.0" -t "$ECR:latest" .
# ---------------------------------------------------------------------------
FROM alpine:3.22

COPY book /book
RUN chmod +x /book

EXPOSE 8080
ENTRYPOINT ["/book"]
