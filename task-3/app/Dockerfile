# 앱 3개(user/product/stress) 모두 "바이너리 하나를 :8080로 실행" 구조가 동일 →
# BINARY 인자로 어느 바이너리를 넣을지만 바꾼다. 당일 특정 앱만 빌드가 달라지면
# 이 파일을 복사해 그 앱 전용으로 수정한다 (README 4번은 앱별로 한 줄씩 명시).
# image scan 채점이 있으면 FROM을 스캔 통과 base(alpine 등)로 교체.
FROM gcr.io/distroless/static-debian13:nonroot
WORKDIR /app
ARG BINARY
COPY --chmod=0755 ${BINARY} /app/server
ENTRYPOINT ["/app/server"]
