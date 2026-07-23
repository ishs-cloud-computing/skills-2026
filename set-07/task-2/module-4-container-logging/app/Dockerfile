# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 제공 Dockerfile 은 flask 를 설치하지 않아 그대로는 기동 불가 → 자체 작성.
# app.py 는 빌드 시 provided/Module4-Container-Logging 에서 복사한다 (README, 원본 수정 금지).
FROM python:3.13-slim

WORKDIR /app

RUN pip install --no-cache-dir flask==3.1.3

COPY app.py .

EXPOSE 8080

ENV PYTHONUNBUFFERED=1

CMD ["python", "app.py"]
