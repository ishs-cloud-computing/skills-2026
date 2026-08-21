#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
set -euxo pipefail

dnf -y install docker jq
systemctl enable --now docker

# admin 비번은 Secrets Manager 에서만 읽는다 (userdata 평문 금지)
SECRET=$(aws secretsmanager get-secret-value --region ${region} --secret-id ${secret_arn} --query SecretString --output text)
ADMIN_PW=$(echo "$SECRET" | jq -r .password)

# Keycloak 26: KC_BOOTSTRAP_ADMIN_* (구 KEYCLOAK_ADMIN 은 deprecated)
# ALB(HTTP) 뒤 → http-enabled + proxy-headers=xforwarded, hostname 미지정 시 strict=false
cat > /etc/keycloak.env <<ENVEOF
KC_BOOTSTRAP_ADMIN_USERNAME=${admin_username}
KC_BOOTSTRAP_ADMIN_PASSWORD=$ADMIN_PW
KC_HTTP_ENABLED=true
KC_PROXY_HEADERS=xforwarded
KC_HEALTH_ENABLED=true
%{ if hostname != "" ~}
KC_HOSTNAME=${hostname}
%{ else ~}
KC_HOSTNAME_STRICT=false
%{ endif ~}
%{ if db_host != "" ~}
KC_DB=postgres
KC_DB_URL=jdbc:postgresql://${db_host}:5432/${db_name}
KC_DB_USERNAME=${db_username}
KC_DB_PASSWORD=$(echo "$SECRET" | jq -r .db_password)
%{ endif ~}
ENVEOF
chmod 600 /etc/keycloak.env

docker run -d --name keycloak --restart always \
  -p 8080:8080 -p 9000:9000 \
  --env-file /etc/keycloak.env \
  ${image} start
