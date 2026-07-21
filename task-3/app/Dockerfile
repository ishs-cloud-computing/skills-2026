# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 앱 3개(user/product/stress) 모두 "바이너리 하나를 :8080로 실행" 구조가 동일 →
# BINARY 인자로 어느 바이너리를 넣을지만 바꾼다. 당일 특정 앱만 빌드가 달라지면
# 이 파일을 복사해 그 앱 전용으로 수정한다 (README STEP 4가 3개를 루프로 빌드).
# image scan 채점이 생기면 FROM을 스캔 통과 이미지(alpine 등)로 교체.
#
# distroless base = static + glibc + libssl. 제공 바이너리는 AL2023 기본 빌드(CGO_ENABLED=1)라
# net/os_user가 cgo resolver를 끌어와 glibc에 동적 링크될 가능성이 높다. glibc가 없는
# static 베이스에 넣으면 "exec /app/server: no such file or directory"로 즉사하는데,
# 이 메시지는 바이너리가 없다고 오도한다(실제로 없는 건 ELF 인터프리터). base는
# 정적·동적 둘 다 실행하므로 ~18MB 대가로 이 분기를 없앤다. 확인은 README STEP 4a.
FROM gcr.io/distroless/base-debian13:nonroot
WORKDIR /app
ARG BINARY
COPY --chmod=0755 ${BINARY} /app/server
ENTRYPOINT ["/app/server"]
