# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
#
# 지급 Dockerfile(provided/module-4/Dockerfile) 수정본.
# 지급본은 flask 를 설치하지 않지만 app.py 가 flask 를 import 한다
# (requirements.txt 미지급) → 그대로 빌드하면 ModuleNotFoundError CrashLoop.
# provided/ 는 수정 금지이므로 이 수정본을 CloudShell 빌드에 사용한다 (런북 3단계).
FROM python:3.12-slim
WORKDIR /app
COPY app.py .
RUN pip install --no-cache-dir flask
EXPOSE 8080
CMD ["python", "app.py"]
