# ---------------------------------------------------------------------------
# App Image (요구사항 7) — alpine base
# - Go binary "book" (x86, TCP/8080) 배포 + curl 포함
# - 이미지 <8MB (압축/registry 기준) 유지
# - alpine 기반이라 base 레이어의 /lib/apk/db/installed 패키지 DB 존재
#   → ECR BASIC scanning(Clair)이 정상 COMPLETE 됨 (scratch는 불가)
# - curl 은 무거운 `apk add curl`(brotli/zstd/openssl 등 의존성으로 8MB 초과) 대신
#   정적 빌드(curl-static) 바이너리 1개만 복사해 용량을 억제한다.
#
# 빌드:
#   docker buildx build --platform linux/amd64 --provenance=false \
#     -f Dockerfile -t "$ECR:v1.0.0" --push .
# ---------------------------------------------------------------------------

# 1) book 바이너리 UPX 압축 + 정적 curl 준비
FROM alpine:3.20 AS builder
WORKDIR /out
COPY book /out/book
RUN apk add --no-cache upx curl-static \
    && chmod +x ./book \
    && (upx --best --lzma /out/book || true) \
    && cp /usr/bin/curl /out/curl

# 2) 최종 런타임 이미지 (alpine base + 정적 curl → 스캔 가능 + 경량)
#    ca-certificates-bundle 은 alpine base 에 이미 포함(/etc/ssl/certs/ca-certificates.crt)
FROM alpine:3.20
COPY --from=builder /out/curl /usr/bin/curl
COPY --from=builder /out/book /book
EXPOSE 8080
ENTRYPOINT ["/book"]
