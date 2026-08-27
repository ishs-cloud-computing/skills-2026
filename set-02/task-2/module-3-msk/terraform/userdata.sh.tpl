#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
# set -e 는 일부러 뺀다: 토픽 생성 재시도 루프의 실패가 cloud-final 을 죽이면 안 된다
set -uxo pipefail

# ===== 1) kafka CLI + IAM 인증 jar (토픽 생성용) =====
dnf -y install java-17-amazon-corretto-headless

curl -fsSL "https://archive.apache.org/dist/kafka/${kafka_version}/kafka_2.13-${kafka_version}.tgz" -o /tmp/kafka.tgz
mkdir -p /opt/kafka
tar -xzf /tmp/kafka.tgz -C /opt/kafka --strip-components=1
rm -f /tmp/kafka.tgz
curl -fsSL "https://github.com/aws/aws-msk-iam-auth/releases/download/v${msk_iam_auth_version}/aws-msk-iam-auth-${msk_iam_auth_version}-all.jar" \
  -o /opt/kafka/libs/aws-msk-iam-auth-all.jar

cat > /opt/kafka/client.properties <<'EOF'
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF

# ===== 2) 토픽 생성 (과제지 3. MSK Topic — RF/파티션 정확 일치) =====
# EC2 는 MSK ACTIVE 후 생성되지만 브로커 기동 직후 잠깐 실패할 수 있어 재시도
create_topic() {
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "${bootstrap_servers_iam}" \
    --command-config /opt/kafka/client.properties \
    --create --if-not-exists --topic "$1" --partitions "$2" --replication-factor "$3"
}

for i in $(seq 1 30); do
  if create_topic "${raw_topic_name}" "${raw_partitions}" "${raw_rf}" \
     && create_topic "${alert_topic_name}" "${alert_partitions}" "${alert_rf}"; then
    break
  fi
  sleep 10
done

# ===== 3) Producer 앱 (Application.md: 백그라운드 + 재부팅 생존 → systemd) =====
mkdir -p /opt/app
aws s3 cp "s3://${app_bucket}/${app_key}" /opt/app/app
chmod +x /opt/app/app

cat > /etc/systemd/system/app.service <<'EOF'
[Unit]
Description=wsc2026 sensor producer
After=network-online.target
Wants=network-online.target

[Service]
# tls: 제공 바이너리(9094 비인증 TLS). iam: 자체 IAM 전용 바이너리(SASL/IAM 9098, AWS_REGION 으로 signer 리전 지정).
# 바이너리 선택은 producer_auth_mode 로 결정(s3.tf), 엔드포인트는 그에 맞춰 주입된다.
Environment=BOOTSTRAP_SERVERS=${app_bootstrap_servers}
Environment=TOPIC_RAW=${raw_topic_name}
Environment=AWS_REGION=${region}
ExecStart=/opt/app/app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now app
