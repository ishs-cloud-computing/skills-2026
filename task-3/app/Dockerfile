# 만약 image scan을 해야하는 경우, alpine linux로 변경
FROM gcr.io/distroless/static-debian13:nonroot # 만약 image scan이 필수라면 alpine으로 변경
WORKDIR /app
COPY {Binary} /app/server
ENTRYPOINT ["server"]
