# syntax=docker/dockerfile:1
# book 컨테이너 이미지 (요구사항 5: ECR 이미지 크기 <= 3MB).
# 제공된 정적 Go 바이너리(수정 금지)를 scratch 에 그대로 담는다. 크기는 빌드 시
# zstd 레이어 압축(buildx --output ...,compression=zstd)으로 3MB 이하로 맞춘다.
# build context = set-06/task-1 (provided/ 참조). `-f app/Dockerfile` 로 빌드.

# CA 인증서만 추출 (book 이 DynamoDB(VPCe)로 HTTPS 호출 시 x509 검증에 필요)
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS certs
RUN dnf install -y ca-certificates >/dev/null && update-ca-trust

FROM scratch
COPY --from=certs /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
COPY provided/book-linux-amd64_v1.0.1 /book
EXPOSE 8080
ENTRYPOINT ["/book"]
