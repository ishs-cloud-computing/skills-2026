# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 바이너리 빌드 형식때문에 실행되지 않는다면, golang:1.26-alpine과 같은 이미지로 교체한다.
FROM gcr.io/distroless/base-debian13:nonroot
WORKDIR /app
COPY --chmod=0755 user ./

# Application에 필요한 환경 변수 추가
ENV key=value

ENTRYPOINT ["/app/server"]
