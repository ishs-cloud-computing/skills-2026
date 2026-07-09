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

# 만약 arm64라면 https://github.com/ishs-cloud-computing/alpine-curl/pkgs/container/alpine-curl/tag=latest 해당 페이지에서 OS / Arch 선택 후 변경
FROM ghcr.io/ishs-cloud-computing/alpine-curl:3.23 
WORKDIR /app
COPY --chmod=0755 book /app/book
ENTRYPOINT ["/app/book"]
