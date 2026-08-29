# NOTES.md §3.3 — 채점 2-2: imageSizeInBytes(압축 크기) <= 3MB
# 실측(v1.0.1, 8.4MB): zstd -19/-22 모두 3.07MB 로 초과 → UPX 로 바이너리 자체를 선압축(레이어 압축만으론 불가).
# 원본 제공 파일은 무수정 — 빌드 단계에서만 압축한다. 빌드 명령은 README 런북 2단계.
# CA 필수 — scratch 에는 신뢰 저장소가 없어 STS/DynamoDB TLS 가 x509 unknown authority 로
# 전멸한다 (실측 8-2 504 원인). 전체 번들(+0.5MB)은 3MB 초과 → AWS 체인 루트만 추출(~7KB).
FROM public.ecr.aws/docker/library/alpine:3.22 AS build
RUN apk add --no-cache ca-certificates upx >/dev/null && \
    cat /usr/share/ca-certificates/mozilla/Amazon_Root_CA_*.crt \
        /usr/share/ca-certificates/mozilla/Starfield_*G2.crt > /aws-roots.pem
COPY book-linux-amd64_v1.0.1 /book
RUN upx -q --best --lzma /book

FROM scratch
COPY --from=build /aws-roots.pem /etc/ssl/certs/ca-certificates.crt
COPY --from=build /book /book
EXPOSE 8080
ENTRYPOINT ["/book"]
