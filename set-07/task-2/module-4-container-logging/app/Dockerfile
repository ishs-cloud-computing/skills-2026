# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
#
# 지급 Dockerfile 의 2026-08-01 정정 반영본
# (= provided/module-4/Dockerfile-2026-08-01, SPDX 헤더만 다름).
# 최초 지급본은 flask 를 설치하지 않아 app.py 가 ModuleNotFoundError 로 CrashLoop 했고,
# 출제자가 3행에 pip install 을 삽입하는 것으로 정정했다 (task-2/2과제.txt Module 4).
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir Flask==3.1.3
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
