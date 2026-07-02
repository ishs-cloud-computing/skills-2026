# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Book App Image (요구사항 5 / 6) — 제공된 정적 Go 바이너리(book)를 그대로 실행
# - 베이스는 고정 버전 alpine: ECR Basic 스캔(Clair)은 scratch 를 스캔하지 못하고,
#   alpine 은 ca-certificates-bundle 기본 포함(DynamoDB TLS 필요)
# - tzdata + TZ=Asia/Seoul: book 은 tzdata 미내장 Go 바이너리라 zoneinfo 가 없으면
#   created_at 이 UTC 로 저장된다 (Reference03: KST, mark 9-2)
# - Critical/High 취약점 금지(mark 3-1) → 최신 안정 alpine 로 고정, 필요 시
#   `apk upgrade --no-cache` 라인 추가로 패치 (README 주의사항 참고)
#
# 빌드(과제 디렉토리에서, 제공자료를 컨텍스트로 사용 — 복사/수정 없음):
#   docker buildx build --platform linux/amd64 --provenance=false \
#     -f app/Dockerfile -t "$ECR:stable" --push ../../shared/provided/task-1
# ---------------------------------------------------------------------------
FROM alpine:3.24.1

RUN apk add --no-cache tzdata && adduser -D -u 10001 book

ENV TZ=Asia/Seoul

COPY --chmod=755 book /book

USER book
EXPOSE 8080
ENTRYPOINT ["/book"]
