# 빌드 컨텍스트: shared/provided/task-1 (제공 원본 그대로 사용)
# book은 정적 링크 x86-64 바이너리 — 이미지도 linux/amd64로 빌드/푸시해야 함
FROM public.ecr.aws/docker/library/alpine:3.23

# AWS API(DynamoDB) TLS 통신에 CA 번들 필요
RUN apk add --no-cache ca-certificates

COPY book /app/book
RUN chmod +x /app/book

EXPOSE 8080
ENTRYPOINT ["/app/book"]
