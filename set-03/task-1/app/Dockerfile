# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Book App Image (요구사항 4·6)
# - 제공된 Go binary "book" (x86-64, TCP/8080) 배포.
#   book 은 이 디렉토리(app/)에 있다고 가정한다 — 원본 shared/provided/task-1/book 을
#   런북 step 0 에서 app/ 로 복사한다 (원본 수정 금지, 복사본은 .gitignore 제외).
# - alpine 기반: ECR Basic scanning 이 OS 패키지 DB 를 읽어 스캔 COMPLETE 됨.
#   최신 패치 alpine 으로 공개 취약점 0 유지 (요구사항 6: 취약점 존재 금지).
# - 태그는 v1.0.0 하나만 push (요구사항 6: v1.0.0 외 이미지 존재 금지 → latest 금지).
#
# 빌드/푸시 (인터넷 가능 환경, app/ 에서):
#   docker buildx build --platform linux/amd64 --provenance=false \
#     -t "$ECR:v1.0.0" --push .
# ---------------------------------------------------------------------------
FROM alpine:3.22

COPY book /book
RUN chmod +x /book

EXPOSE 8080
ENTRYPOINT ["/book"]
