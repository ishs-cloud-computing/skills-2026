# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
# 지급 worker.py 무수정 사용 (과제지 6-5: boto3 포함, Dockerfile 직접 작성).
# 빌드 컨텍스트에 provided/module-4/worker.py 를 복사해 두고 빌드한다
# (README 3단계 CloudShell — cp ../provided/module-4/worker.py .)
FROM public.ecr.aws/docker/library/python:3.12-slim
RUN pip install --no-cache-dir boto3
COPY worker.py /app/worker.py
CMD ["python", "-u", "/app/worker.py"]
