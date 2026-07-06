# 제공 바이너리는 x86 AL2023에서 빌드/검증됨 → 동일 런타임 사용 (musl 호환성 리스크 제거)
FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal
ARG BINARY
COPY ${BINARY} /app
EXPOSE 8080
ENTRYPOINT ["/app"]
