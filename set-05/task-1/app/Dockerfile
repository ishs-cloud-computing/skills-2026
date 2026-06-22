# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# App Image (요구사항 7) — alpine base + 정적 curl(소스 빌드)
# - Go binary "book" (x86, TCP/8080) 배포 + curl 포함
# - alpine 기반이라 base 레이어에 apk 패키지 DB(/lib/apk/db/installed) 존재
#   → ECR BASIC scanning(Clair)이 정상 COMPLETE 됨 (scratch는 불가)
# - curl 은 `apk add curl`(openssl/brotli/zstd/nghttp2/idn2 등 의존성으로 ECR 8.3MB
#   초과) 대신, 공식 curl 소스(curl.se, sha256 검증)를 HTTP/HTTPS 최소 기능으로
#   정적 빌드 → UPX 압축한 단일 바이너리(≈1.7MB)만 복사한다.
#   추가 .so 의존성이 없어 base alpine 의 ca-certificates-bundle 만으로 HTTPS 동작.
#   → ECR(압축) 이미지 ≈ 7.6MB < 8MB 유지.
#
# 빌드 (bastion, 인터넷 O):
#   docker buildx build --platform linux/amd64 --provenance=false \
#     -f Dockerfile -t "$ECR:v1.0.0" --push .
# ---------------------------------------------------------------------------

ARG CURL_VERSION=8.11.1
# curl-${CURL_VERSION}.tar.xz 소스 아카이브의 sha256 (무결성 검증용)
ARG CURL_SHA256=c7ca7db48b0909743eaef34250da02c19bc61d4f1dcedd6603f109409536ab56

# 1) book UPX 압축 + 정적 curl 소스 빌드(HTTP/HTTPS 전용) + UPX 압축
FROM alpine:3.20 AS builder
ARG CURL_VERSION
ARG CURL_SHA256
WORKDIR /src
COPY book /book
ADD --checksum=sha256:${CURL_SHA256} \
    https://curl.se/download/curl-${CURL_VERSION}.tar.xz /src/curl.tar.xz
RUN apk add --no-cache build-base tar xz pkgconf perl upx \
        openssl-dev openssl-libs-static zlib-dev zlib-static \
    && tar -xJf curl.tar.xz && cd "curl-${CURL_VERSION}" \
    && PKG_CONFIG="pkg-config --static" ./configure \
        --disable-shared --enable-static --with-openssl \
        --without-libpsl --without-brotli --without-zstd --without-libidn2 \
        --without-nghttp2 --without-ngtcp2 --without-libssh2 --without-librtmp \
        --disable-ldap --disable-ldaps --disable-rtsp --disable-dict --disable-telnet \
        --disable-tftp --disable-pop3 --disable-imap --disable-smtp --disable-gopher \
        --disable-mqtt --disable-smb --disable-manual --disable-ares CFLAGS="-Os" \
    && make -j"$(nproc)" LDFLAGS="-all-static -s" \
    && cp src/curl /curl && strip /curl \
    && chmod +x /book \
    && (upx --best --lzma /book || true) \
    && (upx --best --lzma /curl || true)

# 2) 최종 런타임 이미지 (alpine base + 정적 curl → 스캔 가능 + 경량)
#    정적 curl 은 자체 musl/OpenSSL 을 포함해 추가 .so 의존성이 없음
FROM alpine:3.20
COPY --from=builder /curl /usr/bin/curl
COPY --from=builder /book /book
EXPOSE 8080
ENTRYPOINT ["/book"]
