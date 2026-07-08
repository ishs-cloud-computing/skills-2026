# 제공 바이너리는 x86 AL2023에서 빌드/검증됨 → 동일 런타임 사용 (musl 호환성 리스크 제거)
FROM gcr.io/distroless/static-debian13:nonroot
WORKDIR /app
COPY {Binary} /app/app
CMD ["app"]
