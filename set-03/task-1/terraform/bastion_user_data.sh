#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# bastion 부팅 시 1회. AL2023 에는 ssm-agent 가 이미 있고 jq 는 없다.
set -eux

dnf install -y jq tar unzip

curl -sLo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# aws login --remote (README step 4) 는 AWS CLI 2.32.0 이상이 필요하고
# AL2023 의 dnf 기본 버전은 그 아래일 수 있다.
curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
unzip -q -o /tmp/awscli.zip -d /tmp
/tmp/aws/install --update
