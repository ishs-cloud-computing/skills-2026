# syntax=docker/dockerfile:1
# Bottlerocket bootstrap container 이미지. bash/curl/chroot 가 필요하므로 AL2023 사용.
# bootstrap container 는 이미지의 ENTRYPOINT 를 실행하므로 스크립트를 내장한다.
# (role 은 user-data 로 주입). build context = set-06/task-1, `-f app/bootstrap/Dockerfile`.
FROM public.ecr.aws/amazonlinux/amazonlinux:2023

COPY app/bootstrap/set-hostname.sh /usr/local/bin/set-hostname.sh
RUN chmod +x /usr/local/bin/set-hostname.sh

ENTRYPOINT ["/usr/local/bin/set-hostname.sh"]
