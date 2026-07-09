# 만약 image scan을 해야하는 경우, alpine linux로 변경
FROM gcr.io/distroless/static-debian13:nonroot 
WORKDIR /app
COPY {Binary} /app/server
ENTRYPOINT ["/app/server"]
